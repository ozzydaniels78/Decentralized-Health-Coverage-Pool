
;; title: Decentralized-Health-Coverage-Pool
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-CLAIM-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-MEMBER (err u104))
(define-constant MIN-CONTRIBUTION u1000000)
(define-constant CLAIM-REVIEW-THRESHOLD u5000000)

(define-data-var pool-balance uint u0)
(define-data-var total-members uint u0)
(define-data-var admin principal tx-sender)

(define-map members principal 
  {
    balance: uint,
    joined-height: uint,
    total-claims: uint
  }
)

(define-map claims uint 
  {
    member: principal,
    amount: uint,
    status: (string-ascii 20),
    evidence: (string-ascii 256),
    stacks-block-height: uint
  }
)

(define-data-var claim-nonce uint u0)

(define-public (initialize-pool (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (var-set admin new-admin)
    (ok true)))
(define-public (join-pool (contribution uint))
  (begin
    (asserts! (>= contribution MIN-CONTRIBUTION) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? members tx-sender)) ERR-ALREADY-MEMBER)
    (try! (stx-transfer? contribution tx-sender (as-contract tx-sender)))
    (map-set members tx-sender
      {
        balance: contribution,
        joined-height: stacks-block-height,
        total-claims: u0
      })
    (var-set pool-balance (+ (var-get pool-balance) contribution))
    (var-set total-members (+ (var-get total-members) u1))
    (ok true)))

(define-public (contribute (amount uint))
  (let ((member-data (unwrap! (map-get? members tx-sender) (err u101))))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set members tx-sender
      (merge member-data {balance: (+ (get balance member-data) amount)}))
    (var-set pool-balance (+ (var-get pool-balance) amount))
    (ok true)))
(define-public (submit-claim (amount uint) (evidence (string-ascii 256)))
  (let (
    (claim-id (var-get claim-nonce))
    (member-data (unwrap! (map-get? members tx-sender) (err u101)))
  )
    (asserts! (< amount (var-get pool-balance)) ERR-INSUFFICIENT-FUNDS)
    (map-set claims claim-id
      {
        member: tx-sender,
        amount: amount,
        status: "PENDING",
        evidence: evidence,
        stacks-block-height: stacks-block-height
      })
    (var-set claim-nonce (+ claim-id u1))
    (ok claim-id)))
(define-public (approve-claim (claim-id uint))
  (let (
    (claim (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND))
    (member-data (unwrap! (map-get? members (get member claim)) (err u101)))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u101))
    (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get member claim))))
    (map-set claims claim-id (merge claim {status: "APPROVED"}))
    (map-set members (get member claim)
      (merge member-data {total-claims: (+ (get total-claims member-data) u1)}))
    (var-set pool-balance (- (var-get pool-balance) (get amount claim)))
    (ok true)))
(define-public (reject-claim (claim-id uint))
  (let ((claim (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
    (asserts! (is-eq tx-sender (var-get admin)) (err u101))
    (map-set claims claim-id (merge claim {status: "REJECTED"}))
    (ok true)))

(define-read-only (get-pool-balance)
  (ok (var-get pool-balance)))

(define-read-only (get-member-data (member principal))
  (ok (map-get? members member)))

(define-read-only (get-claim (claim-id uint))
  (ok (map-get? claims claim-id)))

(define-read-only (get-total-members)
  (ok (var-get total-members)))
