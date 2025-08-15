
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

(define-constant ERR-MEMBER-INACTIVE (err u105))
(define-constant ERR-APPROVER-EXISTS (err u106))
(define-constant ERR-APPROVER-NOT-FOUND (err u107))
(define-constant ERR-ALREADY-VOTED (err u108))
(define-constant ERR-INVALID-CLAIM-STATUS (err u109))
(define-constant ERR-LIST-OVERFLOW (err u110))
(define-constant ERR-NO-WITHDRAWAL-REQUEST (err u111))
(define-constant ERR-WITHDRAWAL-COOLING-PERIOD (err u112))
(define-constant ERR-INSUFFICIENT-MEMBER-BALANCE (err u113))
(define-constant MIN-CONTRIBUTION u1000000)
(define-constant CLAIM-REVIEW-THRESHOLD u5000000)
(define-constant EMERGENCY-WITHDRAWAL-COOLING-PERIOD u1008)
(define-constant EMERGENCY-WITHDRAWAL-PENALTY-PERCENT u10)

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

(define-constant PREMIUM-PERIOD u144)
(define-constant DEFAULT-PREMIUM-AMOUNT u100000)

(define-data-var base-premium-amount uint DEFAULT-PREMIUM-AMOUNT)

(define-map member-premiums principal
  {
    last-payment-height: uint,
    premium-amount: uint,
    is-active: bool,
    missed-payments: uint
  }
)

(define-public (set-premium-amount (member principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (let ((existing-premium (default-to 
            {last-payment-height: u0, premium-amount: (var-get base-premium-amount), is-active: false, missed-payments: u0}
            (map-get? member-premiums member))))
      (map-set member-premiums member
        (merge existing-premium {premium-amount: amount}))
      (ok true))))

(define-public (pay-premium)
  (let (
    (member-data (unwrap! (map-get? members tx-sender) (err u101)))
    (premium-data (default-to 
      {last-payment-height: u0, premium-amount: (var-get base-premium-amount), is-active: false, missed-payments: u0}
      (map-get? member-premiums tx-sender)))
  )
    (try! (stx-transfer? (get premium-amount premium-data) tx-sender (as-contract tx-sender)))
    (map-set member-premiums tx-sender
      {
        last-payment-height: stacks-block-height,
        premium-amount: (get premium-amount premium-data),
        is-active: true,
        missed-payments: u0
      })
    (var-set pool-balance (+ (var-get pool-balance) (get premium-amount premium-data)))
    (ok true)))

(define-public (deactivate-member (member principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (let ((premium-data (unwrap! (map-get? member-premiums member) (err u101))))
      (map-set member-premiums member
        (merge premium-data {is-active: false, missed-payments: (+ (get missed-payments premium-data) u1)}))
      (ok true))))

(define-read-only (is-member-active (member principal))
  (let ((premium-data (map-get? member-premiums member)))
    (match premium-data
      data (and 
             (get is-active data)
             (< (- stacks-block-height (get last-payment-height data)) PREMIUM-PERIOD))
      false)))

(define-read-only (get-member-premium-status (member principal))
  (ok (map-get? member-premiums member)))

(define-public (submit-claim-with-premium-check (amount uint) (evidence (string-ascii 256)))
  (let (
    (claim-id (var-get claim-nonce))
    (member-data (unwrap! (map-get? members tx-sender) (err u101)))
  )
    (asserts! (is-member-active tx-sender) (err u105))
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

    (define-constant MULTISIG-THRESHOLD u3)
(define-constant LARGE-CLAIM-THRESHOLD u5000000)

(define-data-var approver-count uint u0)

(define-map approvers principal bool)

(define-map claim-votes uint
  {
    approvals: uint,
    rejections: uint,
    voters: (list 10 principal)
  }
)

(define-map approver-votes {claim-id: uint, approver: principal} bool)

(define-map emergency-withdrawals principal
  {
    requested-amount: uint,
    request-height: uint,
    is-pending: bool
  }
)

(define-public (add-approver (new-approver principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (asserts! (is-none (map-get? approvers new-approver)) (err u106))
    (map-set approvers new-approver true)
    (var-set approver-count (+ (var-get approver-count) u1))
    (ok true)))

(define-public (remove-approver (approver principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (asserts! (is-some (map-get? approvers approver)) (err u107))
    (map-delete approvers approver)
    (var-set approver-count (- (var-get approver-count) u1))
    (ok true)))

(define-public (vote-on-claim (claim-id uint) (approve bool))
  (let (
    (claim (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND))
    (vote-data (default-to {approvals: u0, rejections: u0, voters: (list)} (map-get? claim-votes claim-id)))
    (existing-vote (map-get? approver-votes {claim-id: claim-id, approver: tx-sender}))
  )
    (asserts! (default-to false (map-get? approvers tx-sender)) (err u100))
    (asserts! (is-none existing-vote) (err u108))
    (asserts! (is-eq (get status claim) "PENDING") (err u109))
    
    (map-set approver-votes {claim-id: claim-id, approver: tx-sender} approve)
    
    (let ((updated-vote-data 
           (if approve
             (merge vote-data {
               approvals: (+ (get approvals vote-data) u1),
               voters: (unwrap! (as-max-len? (append (get voters vote-data) tx-sender) u10) (err u110))
             })
             (merge vote-data {
               rejections: (+ (get rejections vote-data) u1),
               voters: (unwrap! (as-max-len? (append (get voters vote-data) tx-sender) u10) (err u110))
             }))))
      
      (map-set claim-votes claim-id updated-vote-data)
      
      (if (>= (get approvals updated-vote-data) MULTISIG-THRESHOLD)
        (execute-claim-approval claim-id)
        (if (>= (get rejections updated-vote-data) MULTISIG-THRESHOLD)
          (execute-claim-rejection claim-id)
          (ok true))))))

(define-private (execute-claim-approval (claim-id uint))
  (let (
    (claim (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND))
    (member-data (unwrap! (map-get? members (get member claim)) (err u101)))
  )
    (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get member claim))))
    (map-set claims claim-id (merge claim {status: "APPROVED"}))
    (map-set members (get member claim)
      (merge member-data {total-claims: (+ (get total-claims member-data) u1)}))
    (var-set pool-balance (- (var-get pool-balance) (get amount claim)))
    (ok true)))

(define-private (execute-claim-rejection (claim-id uint))
  (let ((claim (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
    (map-set claims claim-id (merge claim {status: "REJECTED"}))
    (ok true)))

(define-public (submit-large-claim (amount uint) (evidence (string-ascii 256)))
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
    (map-set claim-votes claim-id {approvals: u0, rejections: u0, voters: (list)})
    (var-set claim-nonce (+ claim-id u1))
    (ok claim-id)))

(define-read-only (get-claim-votes (claim-id uint))
  (ok (map-get? claim-votes claim-id)))

(define-read-only (is-approver (principal-check principal))
  (default-to false (map-get? approvers principal-check)))

(define-read-only (get-approver-count)
  (ok (var-get approver-count)))

(define-public (request-emergency-withdrawal (amount uint))
  (let (
    (member-data (unwrap! (map-get? members tx-sender) (err u101)))
    (existing-request (map-get? emergency-withdrawals tx-sender))
  )
    (asserts! (<= amount (get balance member-data)) ERR-INSUFFICIENT-MEMBER-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none existing-request) (err u101))
    
    (map-set emergency-withdrawals tx-sender
      {
        requested-amount: amount,
        request-height: stacks-block-height,
        is-pending: true
      })
    (ok true)))

(define-public (execute-emergency-withdrawal)
  (let (
    (withdrawal-data (unwrap! (map-get? emergency-withdrawals tx-sender) ERR-NO-WITHDRAWAL-REQUEST))
    (member-data (unwrap! (map-get? members tx-sender) (err u101)))
    (blocks-passed (- stacks-block-height (get request-height withdrawal-data)))
    (penalty-amount (/ (* (get requested-amount withdrawal-data) EMERGENCY-WITHDRAWAL-PENALTY-PERCENT) u100))
    (final-amount (- (get requested-amount withdrawal-data) penalty-amount))
  )
    (asserts! (get is-pending withdrawal-data) (err u101))
    (asserts! (>= blocks-passed EMERGENCY-WITHDRAWAL-COOLING-PERIOD) ERR-WITHDRAWAL-COOLING-PERIOD)
    (asserts! (<= (get requested-amount withdrawal-data) (get balance member-data)) ERR-INSUFFICIENT-MEMBER-BALANCE)
    
    (try! (as-contract (stx-transfer? final-amount tx-sender tx-sender)))
    
    (map-set members tx-sender
      (merge member-data {balance: (- (get balance member-data) (get requested-amount withdrawal-data))}))
    
    (var-set pool-balance (- (var-get pool-balance) final-amount))
    
    (map-delete emergency-withdrawals tx-sender)
    (ok final-amount)))

(define-public (cancel-emergency-withdrawal)
  (let ((withdrawal-data (unwrap! (map-get? emergency-withdrawals tx-sender) ERR-NO-WITHDRAWAL-REQUEST)))
    (map-delete emergency-withdrawals tx-sender)
    (ok true)))

(define-public (admin-approve-emergency-withdrawal (member principal))
  (let (
    (withdrawal-data (unwrap! (map-get? emergency-withdrawals member) ERR-NO-WITHDRAWAL-REQUEST))
    (member-data (unwrap! (map-get? members member) (err u101)))
    (withdrawal-amount (get requested-amount withdrawal-data))
  )
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (asserts! (get is-pending withdrawal-data) (err u101))
    (asserts! (<= withdrawal-amount (get balance member-data)) ERR-INSUFFICIENT-MEMBER-BALANCE)
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender member)))
    
    (map-set members member
      (merge member-data {balance: (- (get balance member-data) withdrawal-amount)}))
    
    (var-set pool-balance (- (var-get pool-balance) withdrawal-amount))
    
    (map-delete emergency-withdrawals member)
    (ok withdrawal-amount)))

(define-read-only (get-emergency-withdrawal-request (member principal))
  (ok (map-get? emergency-withdrawals member)))

(define-read-only (get-withdrawal-cooldown-remaining (member principal))
  (let ((withdrawal-data (map-get? emergency-withdrawals member)))
    (match withdrawal-data
      data 
        (let ((blocks-passed (- stacks-block-height (get request-height data))))
          (if (>= blocks-passed EMERGENCY-WITHDRAWAL-COOLING-PERIOD)
            (ok u0)
            (ok (- EMERGENCY-WITHDRAWAL-COOLING-PERIOD blocks-passed))))
      (ok u0))))