;; Counterfeit Prevention Contract
;; Verifies product authenticity at each supply chain stage

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-PRODUCT-EXISTS (err u401))
(define-constant ERR-PRODUCT-NOT-FOUND (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-INVALID-SIGNATURE (err u404))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map authentic-products
  { product-id: uint }
  {
    creator: principal,
    creation-hash: (buff 32),
    current-owner: principal,
    verification-count: uint,
    is-authentic: bool,
    creation-timestamp: uint
  }
)

(define-map product-transfers
  { product-id: uint, transfer-id: uint }
  {
    from-owner: principal,
    to-owner: principal,
    transfer-hash: (buff 32),
    timestamp: uint,
    verified: bool
  }
)

(define-map product-verifications
  { product-id: uint, verifier: principal }
  {
    verification-timestamp: uint,
    verification-result: bool,
    verifier-signature: (buff 65),
    notes: (string-ascii 300)
  }
)

(define-map authorized-verifiers
  { verifier: principal }
  {
    name: (string-ascii 200),
    verification-level: uint,
    is-active: bool
  }
)

;; Data variables
(define-data-var next-transfer-id uint u1)

;; Read-only functions
(define-read-only (get-product-authenticity (product-id uint))
  (map-get? authentic-products { product-id: product-id })
)

(define-read-only (get-product-transfer (product-id uint) (transfer-id uint))
  (map-get? product-transfers { product-id: product-id, transfer-id: transfer-id })
)

(define-read-only (get-verification (product-id uint) (verifier principal))
  (map-get? product-verifications { product-id: product-id, verifier: verifier })
)

(define-read-only (is-verifier-authorized (verifier principal))
  (match (map-get? authorized-verifiers { verifier: verifier })
    auth-info (get is-active auth-info)
    false
  )
)

(define-read-only (verify-product (product-id uint))
  (match (map-get? authentic-products { product-id: product-id })
    product (get is-authentic product)
    false
  )
)

(define-read-only (get-current-owner (product-id uint))
  (match (map-get? authentic-products { product-id: product-id })
    product (some (get current-owner product))
    none
  )
)

;; Public functions
(define-public (authorize-verifier (verifier principal) (name (string-ascii 200)) (verification-level uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= verification-level u1) (<= verification-level u5)) ERR-INVALID-INPUT)

    (map-set authorized-verifiers
      { verifier: verifier }
      {
        name: name,
        verification-level: verification-level,
        is-active: true
      }
    )

    (ok true)
  )
)

(define-public (register-authentic-product (product-id uint) (creation-hash (buff 32)))
  (begin
    (asserts! (> (len creation-hash) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? authentic-products { product-id: product-id })) ERR-PRODUCT-EXISTS)

    (map-set authentic-products
      { product-id: product-id }
      {
        creator: tx-sender,
        creation-hash: creation-hash,
        current-owner: tx-sender,
        verification-count: u0,
        is-authentic: true,
        creation-timestamp: block-height
      }
    )

    (ok true)
  )
)

(define-public (transfer-product (product-id uint) (to-owner principal) (transfer-hash (buff 32)))
  (let (
    (product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
    (transfer-id (var-get next-transfer-id))
  )
    (asserts! (is-eq tx-sender (get current-owner product)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len transfer-hash) u0) ERR-INVALID-INPUT)

    (map-set product-transfers
      { product-id: product-id, transfer-id: transfer-id }
      {
        from-owner: tx-sender,
        to-owner: to-owner,
        transfer-hash: transfer-hash,
        timestamp: block-height,
        verified: false
      }
    )

    (map-set authentic-products
      { product-id: product-id }
      (merge product { current-owner: to-owner })
    )

    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

(define-public (verify-product-authenticity (product-id uint) (verifier-signature (buff 65)) (notes (string-ascii 300)))
  (let ((product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND)))
    (asserts! (is-verifier-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len verifier-signature) u0) ERR-INVALID-INPUT)

    (map-set product-verifications
      { product-id: product-id, verifier: tx-sender }
      {
        verification-timestamp: block-height,
        verification-result: true,
        verifier-signature: verifier-signature,
        notes: notes
      }
    )

    (map-set authentic-products
      { product-id: product-id }
      (merge product { verification-count: (+ (get verification-count product) u1) })
    )

    (ok true)
  )
)

(define-public (mark-counterfeit (product-id uint) (evidence-notes (string-ascii 300)))
  (let ((product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND)))
    (asserts! (is-verifier-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set authentic-products
      { product-id: product-id }
      (merge product { is-authentic: false })
    )

    (map-set product-verifications
      { product-id: product-id, verifier: tx-sender }
      {
        verification-timestamp: block-height,
        verification-result: false,
        verifier-signature: 0x00,
        notes: evidence-notes
      }
    )

    (ok true)
  )
)

(define-public (verify-transfer (product-id uint) (transfer-id uint))
  (let ((transfer (unwrap! (map-get? product-transfers { product-id: product-id, transfer-id: transfer-id }) ERR-PRODUCT-NOT-FOUND)))
    (asserts! (is-verifier-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set product-transfers
      { product-id: product-id, transfer-id: transfer-id }
      (merge transfer { verified: true })
    )

    (ok true)
  )
)

(define-public (revoke-verifier (verifier principal))
  (let ((verifier-info (unwrap! (map-get? authorized-verifiers { verifier: verifier }) ERR-PRODUCT-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set authorized-verifiers
      { verifier: verifier }
      (merge verifier-info { is-active: false })
    )

    (ok true)
  )
)
