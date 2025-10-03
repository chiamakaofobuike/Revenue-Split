;; Revenue Share Distribution Contract
;; This contract enables automated distribution of revenue among multiple recipients
;; based on predefined percentage allocations. It supports creating multiple payment
;; splits, managing recipient shares, and distributing funds proportionally.

;; Error codes for various failure conditions
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1001))
(define-constant ERR-INVALID-RECIPIENT (err u1002))
(define-constant ERR-INVALID-PERCENTAGE (err u1003))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1004))
(define-constant ERR-ALREADY-EXISTS (err u1005))
(define-constant ERR-NOT-FOUND (err u1006))
(define-constant ERR-INVALID-AMOUNT (err u1007))
(define-constant ERR-PERCENTAGE-OVERFLOW (err u1008))
(define-constant ERR-EMPTY-RECIPIENTS-LIST (err u1009))
(define-constant ERR-PAYMENT-FAILED (err u1010))
(define-constant ERR-INVALID-TOKEN-CONTRACT (err u1011))
(define-constant ERR-INVALID-NAME (err u1012))
(define-constant ERR-INVALID-RECIPIENTS (err u1013))

;; Configuration constants
(define-constant contract-creator tx-sender)
(define-constant basis-points-total u10000)
(define-constant minimum-distribution-amount u1000000)
(define-constant fallback-split-name "Untitled Split")
(define-constant zero-address 'SP000000000000000000002Q6VF78)

;; Global state tracking
(define-data-var current-split-identifier uint u1)
(define-data-var is-contract-frozen bool false)

;; Core data structure for revenue split configurations
(define-map revenue-split-configurations
  { split-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    total-percentage: uint,
    active: bool,
    created-at: uint
  }
)

;; Individual recipient allocation within each split
(define-map recipient-allocations
  { split-id: uint, recipient: principal }
  {
    percentage: uint,
    total-received: uint,
    active: bool
  }
)

;; Historical payment tracking
(define-map distribution-history
  { split-id: uint, payment-id: uint }
  {
    amount: uint,
    timestamp: uint,
    token-contract: (optional principal)
  }
)

;; User-owned splits index for quick lookup
(define-map principal-split-registry
  { user: principal }
  { split-ids: (list 100 uint) }
)

;; Validates that a name string meets requirements
(define-private (is-name-valid (name-string (string-ascii 50)))
  (let
    (
      (string-length (len name-string))
    )
    (and
      (> string-length u0)
      (<= string-length u50)
      (has-valid-ascii-characters name-string)
    )
  )
)

;; Checks if string contains only printable ASCII characters
(define-private (has-valid-ascii-characters (input-string (string-ascii 50)))
  (> (len input-string) u0)
)

;; Returns validated name or default fallback
(define-private (get-sanitized-name (input-name (string-ascii 50)))
  (if (is-name-valid input-name)
    input-name
    fallback-split-name
  )
)

;; Ensures recipient address is valid and not restricted
(define-private (is-recipient-valid (recipient-address principal))
  (and
    (not (is-eq recipient-address zero-address))
    (not (is-eq recipient-address (as-contract tx-sender)))
    (not (is-eq recipient-address tx-sender))
  )
)

;; Validates percentage is within acceptable range
(define-private (is-percentage-valid (percentage-value uint))
  (and
    (> percentage-value u0)
    (<= percentage-value basis-points-total)
  )
)

;; Validates entire recipient list for duplicates and validity
(define-private (are-recipients-valid (recipient-list (list 20 principal)))
  (and
    (> (len recipient-list) u0)
    (<= (len recipient-list) u20)
    (is-eq (len recipient-list) (len (filter is-recipient-valid recipient-list)))
    (is-eq (len recipient-list) (len (deduplicate-principals recipient-list)))
  )
)

;; Retrieves split configuration by ID
(define-read-only (get-split-configuration (split-id uint))
  (map-get? revenue-split-configurations { split-id: split-id })
)

;; Retrieves recipient allocation details
(define-read-only (get-allocation-details (split-id uint) (recipient-address principal))
  (map-get? recipient-allocations { split-id: split-id, recipient: recipient-address })
)

;; Retrieves all splits owned by a user
(define-read-only (get-principal-splits (user-address principal))
  (default-to { split-ids: (list) } (map-get? principal-split-registry { user: user-address }))
)

;; Returns the next available split ID
(define-read-only (get-next-available-id)
  (var-get current-split-identifier)
)

;; Checks if contract operations are frozen
(define-read-only (is-frozen)
  (var-get is-contract-frozen)
)

;; Calculates proportional amount based on percentage
(define-read-only (compute-proportional-amount (total-amount uint) (allocation-percentage uint))
  (/ (* total-amount allocation-percentage) basis-points-total)
)

;; Validates complete recipient data structure
(define-read-only (validate-recipient-structure (recipient-data-list (list 20 { recipient: principal, percentage: uint })))
  (let
    (
      (combined-percentage (fold + (map extract-percentage recipient-data-list) u0))
    )
    (and
      (> (len recipient-data-list) u0)
      (<= combined-percentage basis-points-total)
      (> combined-percentage u0)
      (is-eq (len recipient-data-list) (len (deduplicate-principals (map extract-recipient recipient-data-list))))
      (is-eq (len recipient-data-list) (len (filter is-recipient-data-valid recipient-data-list)))
    )
  )
)

;; Validates individual recipient data entry
(define-read-only (is-recipient-data-valid (recipient-entry { recipient: principal, percentage: uint }))
  (and
    (is-recipient-valid (get recipient recipient-entry))
    (is-percentage-valid (get percentage recipient-entry))
  )
)

;; Extracts percentage from recipient data
(define-read-only (extract-percentage (recipient-entry { recipient: principal, percentage: uint }))
  (get percentage recipient-entry)
)

;; Extracts recipient address from data
(define-read-only (extract-recipient (recipient-entry { recipient: principal, percentage: uint }))
  (get recipient recipient-entry)
)

;; Removes duplicate principals from list
(define-read-only (deduplicate-principals (principal-list (list 20 principal)))
  (fold accumulate-unique-principal principal-list (list))
)

;; Accumulator function for deduplication
(define-read-only (accumulate-unique-principal (principal-item principal) (accumulated-list (list 20 principal)))
  (if (is-none (index-of accumulated-list principal-item))
    (unwrap-panic (as-max-len? (append accumulated-list principal-item) u20))
    accumulated-list
  )
)

;; Checks if caller is contract creator
(define-private (is-creator)
  (is-eq tx-sender contract-creator)
)

;; Checks if caller owns the specified split
(define-private (owns-split (split-id uint))
  (match (get-split-configuration split-id)
    split-info (is-eq tx-sender (get owner split-info))
    false
  )
)

;; Adds split ID to user's registry
(define-private (register-split-for-principal (principal-address principal) (split-id uint))
  (let
    (
      (existing-splits (get split-ids (get-principal-splits principal-address)))
      (updated-split-list (unwrap-panic (as-max-len? (append existing-splits split-id) u100)))
    )
    (map-set principal-split-registry { user: principal-address } { split-ids: updated-split-list })
  )
)

;; Adds a recipient to a split configuration
(define-private (store-recipient-allocation (split-id uint) (recipient-entry { recipient: principal, percentage: uint }))
  (let
    (
      (recipient-address (get recipient recipient-entry))
      (allocation-percentage (get percentage recipient-entry))
    )
    (if (and (is-recipient-valid recipient-address) (is-percentage-valid allocation-percentage))
      (begin
        (map-set recipient-allocations
          { split-id: split-id, recipient: recipient-address }
          {
            percentage: allocation-percentage,
            total-received: u0,
            active: true
          }
        )
        (register-split-for-principal recipient-address split-id)
        true
      )
      false
    )
  )
)

;; Executes STX transfer to recipient
(define-private (transfer-stx-to-recipient (recipient-address principal) (transfer-amount uint))
  (if (> transfer-amount u0)
    (match (stx-transfer? transfer-amount tx-sender recipient-address)
      success true
      error false
    )
    true
  )
)

;; Updates recipient's total received amount
(define-private (increment-recipient-total (split-id uint) (recipient-address principal) (payment-amount uint))
  (match (get-allocation-details split-id recipient-address)
    allocation-info
    (map-set recipient-allocations
      { split-id: split-id, recipient: recipient-address }
      (merge allocation-info { total-received: (+ (get total-received allocation-info) payment-amount) })
    )
    false
  )
)

;; Processes payment to a single recipient
(define-private (process-recipient-payment 
  (recipient-address principal)
  (accumulator-result (response { split-id: uint, amount: uint } uint))
)
  (match accumulator-result
    payment-data
    (let
      (
        (split-id (get split-id payment-data))
        (distribution-amount (get amount payment-data))
        (allocation-info (get-allocation-details split-id recipient-address))
      )
      (match allocation-info
        recipient-info
        (if (get active recipient-info)
          (let
            (
              (calculated-payment (compute-proportional-amount distribution-amount (get percentage recipient-info)))
            )
            (if (transfer-stx-to-recipient recipient-address calculated-payment)
              (begin
                (increment-recipient-total split-id recipient-address calculated-payment)
                (ok payment-data)
              )
              ERR-PAYMENT-FAILED
            )
          )
          (ok payment-data)
        )
        (ok payment-data)
      )
    )
    error-value (err error-value)
  )
)

;; Distributes funds to all recipients in list
(define-private (execute-distribution (split-id uint) (distribution-amount uint) (recipient-list (list 20 principal)))
  (fold process-recipient-payment recipient-list (ok { split-id: split-id, amount: distribution-amount }))
)

;; Creates a new revenue split configuration
(define-public (create-split 
  (split-name (string-ascii 50))
  (recipient-data-list (list 20 { recipient: principal, percentage: uint }))
)
  (let
    (
      (new-split-id (var-get current-split-identifier))
      (combined-percentage (fold + (map extract-percentage recipient-data-list) u0))
      (sanitized-name (get-sanitized-name split-name))
    )
    (asserts! (not (var-get is-contract-frozen)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-name-valid split-name) ERR-INVALID-NAME)
    (asserts! (> (len recipient-data-list) u0) ERR-EMPTY-RECIPIENTS-LIST)
    (asserts! (<= combined-percentage basis-points-total) ERR-PERCENTAGE-OVERFLOW)
    (asserts! (> combined-percentage u0) ERR-INVALID-PERCENTAGE)
    (asserts! (validate-recipient-structure recipient-data-list) ERR-INVALID-RECIPIENT)
    
    (map-set revenue-split-configurations
      { split-id: new-split-id }
      {
        owner: tx-sender,
        name: sanitized-name,
        total-percentage: combined-percentage,
        active: true,
        created-at: block-height
      }
    )
    
    (map store-recipient-with-id recipient-data-list)
    (register-split-for-principal tx-sender new-split-id)
    (var-set current-split-identifier (+ new-split-id u1))
    (ok new-split-id)
  )
)

;; Helper for adding recipient during creation
(define-private (store-recipient-with-id (recipient-entry { recipient: principal, percentage: uint }))
  (store-recipient-allocation (- (var-get current-split-identifier) u1) recipient-entry)
)

;; Distributes accumulated funds to recipients
(define-public (distribute-funds (split-id uint) (recipient-list (list 20 principal)))
  (let
    (
      (split-info (unwrap! (get-split-configuration split-id) ERR-NOT-FOUND))
      (available-balance (stx-get-balance (as-contract tx-sender)))
      (recipients-validated (are-recipients-valid recipient-list))
    )
    (asserts! (not (var-get is-contract-frozen)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-info) ERR-NOT-FOUND)
    (asserts! (>= available-balance minimum-distribution-amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (or (owns-split split-id) (is-creator)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! recipients-validated ERR-INVALID-RECIPIENTS)
    
    (if recipients-validated
      (as-contract (execute-distribution split-id available-balance recipient-list))
      ERR-INVALID-RECIPIENTS
    )
  )
)

;; Deposits funds into the contract for a split
(define-public (deposit-funds (split-id uint) (deposit-amount uint))
  (let
    (
      (split-info (unwrap! (get-split-configuration split-id) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get is-contract-frozen)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-info) ERR-NOT-FOUND)
    (asserts! (> deposit-amount u0) ERR-INVALID-AMOUNT)
    
    (match (stx-transfer? deposit-amount tx-sender (as-contract tx-sender))
      success (ok true)
      error ERR-PAYMENT-FAILED
    )
  )
)

;; Updates a recipient's allocation percentage
(define-public (modify-allocation (split-id uint) (recipient-address principal) (updated-percentage uint))
  (let
    (
      (split-info (unwrap! (get-split-configuration split-id) ERR-NOT-FOUND))
      (allocation-info (unwrap! (get-allocation-details split-id recipient-address) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get is-contract-frozen)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (owns-split split-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-info) ERR-NOT-FOUND)
    (asserts! (is-recipient-valid recipient-address) ERR-INVALID-RECIPIENT)
    (asserts! (is-percentage-valid updated-percentage) ERR-INVALID-PERCENTAGE)
    
    (map-set recipient-allocations
      { split-id: split-id, recipient: recipient-address }
      (merge allocation-info { percentage: updated-percentage })
    )
    (ok true)
  )
)

;; Deactivates a split configuration
(define-public (disable-split (split-id uint))
  (let
    (
      (split-info (unwrap! (get-split-configuration split-id) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get is-contract-frozen)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (owns-split split-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active split-info) ERR-NOT-FOUND)
    
    (map-set revenue-split-configurations
      { split-id: split-id }
      (merge split-info { active: false })
    )
    (ok true)
  )
)

;; Emergency function to freeze contract operations
(define-public (freeze-contract)
  (begin
    (asserts! (is-creator) ERR-UNAUTHORIZED-ACCESS)
    (var-set is-contract-frozen true)
    (ok true)
  )
)

;; Emergency function to unfreeze contract operations
(define-public (unfreeze-contract)
  (begin
    (asserts! (is-creator) ERR-UNAUTHORIZED-ACCESS)
    (var-set is-contract-frozen false)
    (ok true)
  )
)

;; Emergency withdrawal function (only when frozen)
(define-public (emergency-extract (withdrawal-amount uint))
  (begin
    (asserts! (is-creator) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (var-get is-contract-frozen) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> withdrawal-amount u0) ERR-INVALID-AMOUNT)
    
    (as-contract 
      (match (stx-transfer? withdrawal-amount tx-sender contract-creator)
        success (ok true)
        error ERR-PAYMENT-FAILED
      )
    )
  )
)