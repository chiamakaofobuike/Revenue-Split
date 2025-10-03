# Revenue Share Distribution Contract

## Overview

This smart contract enables automated distribution of revenue among multiple recipients based on predefined percentage allocations. It supports creating multiple payment splits, managing recipient shares, and distributing funds proportionally across stakeholders.

## Features

- Create multiple revenue split configurations with custom names
- Allocate revenue shares to up to 20 recipients per split
- Distribute funds automatically based on percentage allocations
- Update recipient allocations dynamically
- Track payment history and total amounts received
- Emergency freeze/unfreeze functionality for contract security
- Support for multiple splits per user
- Validation of all inputs to prevent errors

## Constants

### Configuration Constants
- `basis-points-total`: 10,000 (representing 100.00% in basis points)
- `minimum-distribution-amount`: 1,000,000 micro-STX
- `fallback-split-name`: "Untitled Split"
- `zero-address`: SP000000000000000000002Q6VF78

### Error Codes
- `ERR-UNAUTHORIZED-ACCESS` (1001): Caller lacks required permissions
- `ERR-INVALID-RECIPIENT` (1002): Recipient address is invalid
- `ERR-INVALID-PERCENTAGE` (1003): Percentage value out of range
- `ERR-INSUFFICIENT-BALANCE` (1004): Contract balance too low for distribution
- `ERR-ALREADY-EXISTS` (1005): Split configuration already exists
- `ERR-NOT-FOUND` (1006): Split or allocation not found
- `ERR-INVALID-AMOUNT` (1007): Amount must be greater than zero
- `ERR-PERCENTAGE-OVERFLOW` (1008): Total percentage exceeds 100%
- `ERR-EMPTY-RECIPIENTS-LIST` (1009): No recipients provided
- `ERR-PAYMENT-FAILED` (1010): STX transfer failed
- `ERR-INVALID-TOKEN-CONTRACT` (1011): Token contract is invalid
- `ERR-INVALID-NAME` (1012): Split name is invalid
- `ERR-INVALID-RECIPIENTS` (1013): Recipient list validation failed

## Data Structures

### Revenue Split Configuration
Stores the main configuration for each revenue split:
- `owner`: Principal who created and owns the split
- `name`: ASCII string (max 50 characters) for the split
- `total-percentage`: Sum of all recipient percentages
- `active`: Boolean indicating if split is active
- `created-at`: Block height when split was created

### Recipient Allocations
Tracks individual recipient details within a split:
- `percentage`: Allocation percentage in basis points
- `total-received`: Cumulative amount received by recipient
- `active`: Boolean indicating if allocation is active

### Distribution History
Records payment transactions:
- `amount`: Total amount distributed
- `timestamp`: Block height of distribution
- `token-contract`: Optional principal for token contract

## Public Functions

### create-split
Creates a new revenue split configuration.

**Parameters:**
- `split-name` (string-ascii 50): Name for the split
- `recipient-data-list` (list 20): List of recipients with percentages

**Returns:** `(response uint uint)` - Split ID on success

**Validations:**
- Contract must not be frozen
- Name must be valid (1-50 printable ASCII characters)
- At least one recipient required
- Total percentage must not exceed 10,000 basis points
- No duplicate recipients allowed
- All recipients must have valid addresses and percentages

**Example:**
```clarity
(create-split "Project Revenue" 
  (list 
    { recipient: 'SP123..., percentage: u5000 }
    { recipient: 'SP456..., percentage: u3000 }
    { recipient: 'SP789..., percentage: u2000 }
  )
)
```

### deposit-funds
Deposits STX into the contract for a specific split.

**Parameters:**
- `split-id` (uint): ID of the split
- `deposit-amount` (uint): Amount of STX to deposit

**Returns:** `(response bool uint)`

**Validations:**
- Contract must not be frozen
- Split must exist and be active
- Amount must be greater than zero

### distribute-funds
Distributes accumulated funds to all recipients based on their allocations.

**Parameters:**
- `split-id` (uint): ID of the split to distribute
- `recipient-list` (list 20 principal): List of recipient addresses

**Returns:** `(response { split-id: uint, amount: uint } uint)`

**Validations:**
- Contract must not be frozen
- Split must exist and be active
- Contract balance must meet minimum distribution amount
- Caller must be split owner or contract creator
- Recipient list must be valid (no duplicates, valid addresses)

**Notes:**
- Only active recipients receive payments
- Payments are proportional to allocation percentages
- Updates total-received for each recipient

### modify-allocation
Updates a recipient's percentage allocation within a split.

**Parameters:**
- `split-id` (uint): ID of the split
- `recipient-address` (principal): Address of the recipient
- `updated-percentage` (uint): New percentage in basis points

**Returns:** `(response bool uint)`

**Validations:**
- Contract must not be frozen
- Caller must own the split
- Split must exist and be active
- Recipient must exist in the split
- New percentage must be valid (1-10,000 basis points)

### disable-split
Deactivates a split configuration, preventing further operations.

**Parameters:**
- `split-id` (uint): ID of the split to disable

**Returns:** `(response bool uint)`

**Validations:**
- Contract must not be frozen
- Caller must own the split
- Split must exist and be active

### freeze-contract
Emergency function to freeze all contract operations (creator only).

**Returns:** `(response bool uint)`

**Authorization:** Contract creator only

### unfreeze-contract
Emergency function to unfreeze contract operations (creator only).

**Returns:** `(response bool uint)`

**Authorization:** Contract creator only

### emergency-extract
Emergency withdrawal function available only when contract is frozen (creator only).

**Parameters:**
- `withdrawal-amount` (uint): Amount to withdraw

**Returns:** `(response bool uint)`

**Validations:**
- Caller must be contract creator
- Contract must be frozen
- Amount must be greater than zero

## Read-Only Functions

### get-split-configuration
Retrieves split configuration by ID.

**Parameters:**
- `split-id` (uint): ID of the split

**Returns:** `(optional { owner: principal, name: string-ascii 50, total-percentage: uint, active: bool, created-at: uint })`

### get-allocation-details
Retrieves recipient allocation details.

**Parameters:**
- `split-id` (uint): ID of the split
- `recipient-address` (principal): Address of the recipient

**Returns:** `(optional { percentage: uint, total-received: uint, active: bool })`

### get-principal-splits
Retrieves all split IDs owned by a user.

**Parameters:**
- `user-address` (principal): Address of the user

**Returns:** `{ split-ids: (list 100 uint) }`

### get-next-available-id
Returns the next available split ID.

**Returns:** `uint`

### is-frozen
Checks if contract operations are frozen.

**Returns:** `bool`

### compute-proportional-amount
Calculates proportional amount based on percentage.

**Parameters:**
- `total-amount` (uint): Total amount to distribute
- `allocation-percentage` (uint): Percentage in basis points

**Returns:** `uint`

### validate-recipient-structure
Validates complete recipient data structure.

**Parameters:**
- `recipient-data-list` (list 20): List of recipient data

**Returns:** `bool`

## Usage Example

### Creating a Revenue Split

```clarity
;; Create a split for a project with three stakeholders
(contract-call? .revenue-split create-split 
  "Startup Equity"
  (list
    { recipient: 'SP1K1A1PMGW2B..., percentage: u4000 }  ;; 40%
    { recipient: 'SP2K1A1PMGW2B..., percentage: u3500 }  ;; 35%
    { recipient: 'SP3K1A1PMGW2B..., percentage: u2500 }  ;; 25%
  )
)
;; Returns: (ok u1)
```

### Depositing Funds

```clarity
;; Deposit 10 STX into split #1
(contract-call? .revenue-split deposit-funds u1 u10000000)
;; Returns: (ok true)
```

### Distributing Funds

```clarity
;; Distribute accumulated funds to all recipients
(contract-call? .revenue-split distribute-funds 
  u1 
  (list 
    'SP1K1A1PMGW2B... 
    'SP2K1A1PMGW2B... 
    'SP3K1A1PMGW2B...
  )
)
;; Returns: (ok { split-id: u1, amount: u10000000 })
```

### Updating Allocations

```clarity
;; Change recipient's allocation to 45%
(contract-call? .revenue-split modify-allocation 
  u1 
  'SP1K1A1PMGW2B... 
  u4500
)
;; Returns: (ok true)
```

## Security Features

### Access Control
- Split owners can only modify their own splits
- Contract creator has emergency override capabilities
- Recipients cannot modify their own allocations

### Input Validation
- All percentages validated against basis points total
- Recipient addresses checked for validity
- No duplicate recipients allowed in splits
- Name validation ensures printable ASCII characters

### Emergency Controls
- Freeze/unfreeze functionality for security incidents
- Emergency withdrawal available only when frozen
- All operations blocked when contract is frozen

## Best Practices

1. **Percentage Allocation**: Always ensure total percentages do not exceed 10,000 basis points (100%)
2. **Recipient Validation**: Verify all recipient addresses before creating splits
3. **Distribution Timing**: Ensure sufficient balance before distribution (minimum 1,000,000 micro-STX)
4. **Split Management**: Disable splits that are no longer needed
5. **Emergency Procedures**: Only freeze contract in genuine emergencies

## Limitations

- Maximum 20 recipients per split
- Maximum 100 splits per principal
- Maximum 50 characters for split names
- Percentages must be expressed in basis points (1 bp = 0.01%)
- Minimum distribution amount enforced for efficiency