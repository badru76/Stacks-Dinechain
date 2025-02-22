;; DineChain: Enhanced contract

;; Error Codes
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_DINING_SESSION_NOT_FOUND (err u101))
(define-constant ERR_PARTICIPANT_ALREADY_JOINED (err u102))
(define-constant ERR_INSUFFICIENT_PAYMENT_AMOUNT (err u103))
(define-constant ERR_DINING_SESSION_CLOSED (err u104))
(define-constant ERR_INVALID_RESTAURANT_ACCESS (err u105))
(define-constant ERR_DINING_SESSION_EXPIRED (err u106))
(define-constant ERR_INVALID_PAYMENT_AMOUNT (err u107))
(define-constant ERR_MAXIMUM_PARTICIPANTS_REACHED (err u108))
(define-constant ERR_RESTAURANT_ON_BLACKLIST (err u109))
(define-constant ERR_PARTICIPANT_ON_BLACKLIST (err u110))
(define-constant ERR_DINING_SESSION_TIMEOUT (err u111))
(define-constant ERR_DUPLICATE_CLAIM_ATTEMPT (err u112))
(define-constant ERR_UNREGISTERED_RESTAURANT (err u113))
(define-constant ERR_INVALID_SESSION_STATUS (err u114))
(define-constant ERR_RESTAURANT_RATING_ERROR (err u115))

;; Constants
(define-constant MAXIMUM_DINING_PARTICIPANTS u20)
(define-constant DINING_SESSION_TIMEOUT_BLOCKS u144) ;; ~24 hours in blocks
(define-constant MAXIMUM_PAYMENT_AMOUNT u1000000000) ;; Maximum amount in microSTX
(define-constant MINIMUM_PAYMENT_AMOUNT u1000) ;; Minimum amount in microSTX

;; Data Maps
(define-map RestaurantProfiles 
    principal 
    {
        restaurant-name: (string-ascii 50),
        is-verified: bool,
        completed-sessions: uint,
        customer-rating: uint,
        is-blacklisted: bool,
        last-activity-block: uint
    }
)

(define-map DiningSessionDetails
    uint  ;; dining-session-id
    {
        restaurant-principal: principal,
        required-total-amount: uint,
        collected-total-amount: uint,
        participant-count: uint,
        session-status: (string-ascii 10),  ;; "OPEN", "PAID", "CLOSED", "DISPUTED"
        session-creation-block: uint,
        session-expiration-block: uint,
        minimum-participant-payment: uint,
        total-disputes: uint,
        gratuity-percentage: uint
    }
)

(define-map DiningSessionParticipants
    {dining-session-id: uint, participant-principal: principal}
    {
        payment-amount: uint,
        payment-processed: bool,
        participant-join-block: uint,
        gratuity-amount: uint,
        dispute-filed: bool
    }
)

(define-map BlacklistedParticipants principal bool)
(define-map DisputeResolutionDetails uint {dispute-resolved: bool, dispute-winner: principal})
(define-map RestaurantRatingMetrics principal {rating-count: uint, rating-average: uint})

;; Data Variables
(define-data-var dining-session-counter uint u1)
(define-data-var contract-admin principal tx-sender)
(define-data-var contract-emergency-mode bool false)
(define-data-var platform-commission-rate uint u1) ;; 1% platform fee

;; Read-only functions
(define-read-only (get-dining-session-details (dining-session-id uint))
    (map-get? DiningSessionDetails dining-session-id)
)

(define-read-only (get-restaurant-profile (restaurant-principal principal))
    (map-get? RestaurantProfiles restaurant-principal)
)

(define-read-only (get-participant-details (dining-session-id uint) (participant-principal principal))
    (map-get? DiningSessionParticipants 
        {dining-session-id: dining-session-id, participant-principal: participant-principal}
    )
)

(define-read-only (get-restaurant-rating-metrics (restaurant-principal principal))
    (map-get? RestaurantRatingMetrics restaurant-principal)
)

(define-read-only (get-contract-details)
    {
        admin: (var-get contract-admin),
        emergency-mode: (var-get contract-emergency-mode),
        commission-rate: (var-get platform-commission-rate),
        current-session-counter: (var-get dining-session-counter)
    }
)

(define-read-only (get-detailed-session-info (dining-session-id uint))
    (let
        ((session-details (unwrap! (get-dining-session-details dining-session-id) none)))
        (some {
            session: session-details,
            is-expired: (is-session-expired dining-session-id),
            total-with-gratuity: (+ (get collected-total-amount session-details) 
                               (* (get collected-total-amount session-details) 
                                  (get gratuity-percentage session-details)))
        })
    )
)

;; Private functions
(define-private (is-contract-active)
    (not (var-get contract-emergency-mode))
)

(define-private (validate-payment-amount (payment-amount uint))
    (and 
        (>= payment-amount MINIMUM_PAYMENT_AMOUNT)
        (<= payment-amount MAXIMUM_PAYMENT_AMOUNT)
    )
)

(define-private (is-session-expired (dining-session-id uint))
    (let
        ((session-details (unwrap! (map-get? DiningSessionDetails dining-session-id) false)))
        (> block-height (get session-expiration-block session-details))
    )
)

(define-private (calculate-platform-commission (payment-amount uint))
    (/ (* payment-amount (var-get platform-commission-rate)) u100)
)

(define-private (update-restaurant-rating-metrics (restaurant-principal principal) (new-rating uint))
    (let
        ((current-metrics (default-to 
            {rating-count: u0, rating-average: u0}
            (map-get? RestaurantRatingMetrics restaurant-principal))))
        (map-set RestaurantRatingMetrics restaurant-principal
            {
                rating-count: (+ (get rating-count current-metrics) u1),
                rating-average: (/ (+ (* (get rating-average current-metrics) 
                                       (get rating-count current-metrics))
                                    new-rating)
                                 (+ (get rating-count current-metrics) u1))
            }
        )
        (ok true)
    )
)

;; Public functions
(define-public (register-restaurant (restaurant-name (string-ascii 50)))
    (begin
        (asserts! (is-contract-active) ERR_DINING_SESSION_CLOSED)
        (asserts! (is-none (get-restaurant-profile tx-sender)) ERR_UNREGISTERED_RESTAURANT)
        (map-set RestaurantProfiles tx-sender {
            restaurant-name: restaurant-name,
            is-verified: true,
            completed-sessions: u0,
            customer-rating: u0,
            is-blacklisted: false,
            last-activity-block: block-height
        })
        (ok true)
    )
)

(define-public (create-dining-session 
    (restaurant-principal principal) 
    (required-total-amount uint)
    (minimum-participant-payment uint)
    (gratuity-percentage uint))
    (begin
        (asserts! (is-contract-active) ERR_DINING_SESSION_CLOSED)
        (asserts! (validate-payment-amount required-total-amount) ERR_INVALID_PAYMENT_AMOUNT)
        (asserts! (<= gratuity-percentage u30) ERR_INVALID_PAYMENT_AMOUNT) ;; Max 30% gratuity
        (let
            ((dining-session-id (var-get dining-session-counter))
             (restaurant-info (unwrap! (get-restaurant-profile restaurant-principal) ERR_INVALID_RESTAURANT_ACCESS)))
            ;; Additional checks
            (asserts! (not (get is-blacklisted restaurant-info)) ERR_RESTAURANT_ON_BLACKLIST)
            (asserts! (>= (get customer-rating restaurant-info) u1) ERR_UNAUTHORIZED_ACCESS)
            ;; Create session
            (map-set DiningSessionDetails dining-session-id
                {
                    restaurant-principal: restaurant-principal,
                    required-total-amount: required-total-amount,
                    collected-total-amount: u0,
                    participant-count: u0,
                    session-status: "OPEN",
                    session-creation-block: block-height,
                    session-expiration-block: (+ block-height DINING_SESSION_TIMEOUT_BLOCKS),
                    minimum-participant-payment: minimum-participant-payment,
                    total-disputes: u0,
                    gratuity-percentage: gratuity-percentage
                }
            )
            (var-set dining-session-counter (+ dining-session-id u1))
            (ok dining-session-id)
        )
    )
)

(define-public (join-dining-session (dining-session-id uint) (payment-amount uint))
    (begin
        (asserts! (is-contract-active) ERR_DINING_SESSION_CLOSED)
        (let
            ((session-details (unwrap! (get-dining-session-details dining-session-id) ERR_DINING_SESSION_NOT_FOUND))
             (participant-key {dining-session-id: dining-session-id, participant-principal: tx-sender}))
            ;; Enhanced checks
            (asserts! (not (is-session-expired dining-session-id)) ERR_DINING_SESSION_EXPIRED)
            (asserts! (< (get participant-count session-details) MAXIMUM_DINING_PARTICIPANTS) ERR_MAXIMUM_PARTICIPANTS_REACHED)
            (asserts! (>= payment-amount (get minimum-participant-payment session-details)) ERR_INSUFFICIENT_PAYMENT_AMOUNT)
            (asserts! (not (default-to false (map-get? BlacklistedParticipants tx-sender))) ERR_PARTICIPANT_ON_BLACKLIST)
            
            ;; Calculate gratuity and platform commission
            (let
                ((gratuity-amount (/ (* payment-amount (get gratuity-percentage session-details)) u100))
                 (platform-fee (calculate-platform-commission payment-amount)))
                ;; Transfer total amount including gratuity and platform fee
                (try! (stx-transfer? (+ payment-amount gratuity-amount platform-fee) 
                                   tx-sender 
                                   (as-contract tx-sender)))
                
                ;; Update session
                (map-set DiningSessionDetails dining-session-id
                    (merge session-details {
                        collected-total-amount: (+ (get collected-total-amount session-details) payment-amount),
                        participant-count: (+ (get participant-count session-details) u1)
                    })
                )
                
                ;; Add participant
                (map-set DiningSessionParticipants participant-key
                    {
                        payment-amount: payment-amount,
                        payment-processed: false,
                        participant-join-block: block-height,
                        gratuity-amount: gratuity-amount,
                        dispute-filed: false
                    }
                )
                (ok true)
            )
        )
    )
)

(define-public (complete-session-payment (dining-session-id uint))
    (let
        ((session-details (unwrap! (get-dining-session-details dining-session-id) ERR_DINING_SESSION_NOT_FOUND)))
        ;; Verify caller is the restaurant
        (asserts! (is-eq tx-sender (get restaurant-principal session-details)) ERR_UNAUTHORIZED_ACCESS)
        ;; Verify sufficient funds collected
        (asserts! (>= (get collected-total-amount session-details) 
                     (get required-total-amount session-details)) ERR_INSUFFICIENT_PAYMENT_AMOUNT)
        ;; Verify session is open
        (asserts! (is-eq (get session-status session-details) "OPEN") ERR_INVALID_SESSION_STATUS)
        ;; Transfer funds to restaurant
        (try! (as-contract (stx-transfer? 
            (get collected-total-amount session-details)
            tx-sender
            (get restaurant-principal session-details)
        )))
        ;; Update session status
        (map-set DiningSessionDetails dining-session-id
            (merge session-details {session-status: "PAID"})
        )
        (ok true)
    )
)

(define-public (file-dispute (dining-session-id uint))
    (let
        ((session-details (unwrap! (get-dining-session-details dining-session-id) ERR_DINING_SESSION_NOT_FOUND))
         (participant-info (unwrap! (get-participant-details dining-session-id tx-sender) ERR_UNAUTHORIZED_ACCESS)))
        (asserts! (not (get dispute-filed participant-info)) ERR_DUPLICATE_CLAIM_ATTEMPT)
        (asserts! (is-eq (get session-status session-details) "OPEN") ERR_INVALID_SESSION_STATUS)
        (map-set DiningSessionDetails dining-session-id
            (merge session-details {
                total-disputes: (+ (get total-disputes session-details) u1),
                session-status: "DISPUTED"
            })
        )
        (map-set DiningSessionParticipants 
            {dining-session-id: dining-session-id, participant-principal: tx-sender}
            (merge participant-info {dispute-filed: true})
        )
        (ok true)
    )
)

(define-public (claim-payment-refund (dining-session-id uint))
    (let
        ((session-details (unwrap! (get-dining-session-details dining-session-id) ERR_DINING_SESSION_NOT_FOUND))
         (participant-info (unwrap! (get-participant-details dining-session-id tx-sender) ERR_UNAUTHORIZED_ACCESS)))
        (asserts! (is-session-expired dining-session-id) ERR_DINING_SESSION_TIMEOUT)
        (asserts! (not (get payment-processed participant-info)) ERR_DUPLICATE_CLAIM_ATTEMPT)
        ;; Process refund
        (try! (as-contract (stx-transfer? 
            (+ (get payment-amount participant-info) (get gratuity-amount participant-info))
            tx-sender
            tx-sender
        )))
        (map-set DiningSessionParticipants 
            {dining-session-id: dining-session-id, participant-principal: tx-sender}
            (merge participant-info {payment-processed: true})
        )
        (ok true)
    )
)

(define-public (submit-restaurant-rating (restaurant-principal principal) (rating-value uint))
    (begin
        (asserts! (and (>= rating-value u1) (<= rating-value u5)) ERR_INVALID_PAYMENT_AMOUNT)
        (unwrap! (update-restaurant-rating-metrics restaurant-principal rating-value) ERR_RESTAURANT_RATING_ERROR)
        (ok true)
    )
)

(define-public (toggle-emergency-mode)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED_ACCESS)
        (ok (var-set contract-emergency-mode (not (var-get contract-emergency-mode))))
    )
)

(define-public (collect-platform-fees)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED_ACCESS)
        (let
            ((contract-balance (stx-get-balance (as-contract tx-sender))))
            (try! (as-contract (stx-transfer? 
                contract-balance
                tx-sender
                (var-get contract-admin)
            )))
            (ok contract-balance)
        )
    )
)