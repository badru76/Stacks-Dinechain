# DineChain Smart Contract

## Overview
DineChain is a decentralized platform for managing group dining payments and restaurant interactions on the Stacks blockchain. The contract facilitates group dining sessions, handles payments, manages restaurant profiles, and includes features for dispute resolution and rating systems.

## Features
- Restaurant registration and profile management
- Creation and management of dining sessions
- Group payment collection and distribution
- Gratuity handling
- Dispute resolution system
- Restaurant rating system
- Emergency controls
- Platform fee management

## Contract Details
- Platform Fee: 1%
- Maximum Participants per Session: 20
- Session Timeout: 144 blocks (~24 hours)
- Payment Limits:
  - Minimum: 1,000 microSTX
  - Maximum: 1,000,000,000 microSTX
- Maximum Gratuity: 30%

## Core Functions

### Restaurant Management
1. `register-restaurant`
   - Registers a new restaurant on the platform
   - Parameters: restaurant name (max 50 characters)

2. `submit-restaurant-rating`
   - Allows users to rate restaurants (1-5 stars)
   - Updates restaurant's average rating

### Dining Session Management
1. `create-dining-session`
   - Creates a new dining session
   - Parameters: 
     - restaurant principal
     - required total amount
     - minimum participant payment
     - gratuity percentage

2. `join-dining-session`
   - Allows participants to join a session with payment
   - Handles gratuity and platform fees automatically

3. `complete-session-payment`
   - Completes the session and transfers funds to restaurant
   - Only callable by the restaurant

### Dispute Handling
1. `file-dispute`
   - Allows participants to file disputes
   - Changes session status to "DISPUTED"

2. `claim-payment-refund`
   - Processes refunds for eligible participants
   - Available after session expiration

### Administrative Functions
1. `toggle-emergency-mode`
   - Allows admin to pause/resume contract operations
   - Restricted to contract administrator

2. `collect-platform-fees`
   - Allows admin to withdraw accumulated platform fees
   - Restricted to contract administrator

## Status Types
- OPEN: Active session accepting participants
- PAID: Payment completed to restaurant
- CLOSED: Session ended normally
- DISPUTED: Under dispute resolution

## Error Codes
- ERR-UNAUTHORIZED_ACCESS (u100): Unauthorized action attempt
- ERR-DINING_SESSION_NOT_FOUND (u101): Session doesn't exist
- ERR-PARTICIPANT_ALREADY_JOINED (u102): Duplicate participation attempt
- ERR-INSUFFICIENT_PAYMENT_AMOUNT (u103): Payment below required amount
- ERR-DINING_SESSION_CLOSED (u104): Session no longer active
- [Additional error codes documented in contract]

## Security Features
1. Payment validation
2. Participant blacklisting
3. Restaurant verification
4. Emergency shutdown mechanism
5. Transaction timeout protection
6. Duplicate claim prevention

## Read-Only Functions
1. `get-dining-session-details`: Retrieves session information
2. `get-restaurant-profile`: Retrieves restaurant details
3. `get-participant-details`: Retrieves participant information
4. `get-restaurant-rating-metrics`: Retrieves rating statistics
5. `get-contract-details`: Retrieves contract configuration
6. `get-detailed-session-info`: Retrieves comprehensive session data

## Usage Requirements
1. Restaurants must:
   - Register on the platform
   - Maintain a minimum rating
   - Not be blacklisted
   
2. Participants must:
   - Meet minimum payment requirements
   - Not be blacklisted
   - Join before session timeout
   - Pay within session limits

## Best Practices
1. Restaurants should:
   - Verify total amounts before completing sessions
   - Monitor dispute counts
   - Maintain active status

2. Participants should:
   - Verify session details before joining
   - Keep track of session expiration
   - Report disputes promptly

## Technical Integration
Contract interaction requires:
- Stacks wallet integration
- Principal address handling
- STX token management
- Error handling implementation

## Safety Considerations
- All functions include appropriate checks
- Emergency shutdown available
- Timeout protections
- Balance verification
- Access control implementation