;; Decentralized Health Coverage Pool
;; A peer-to-peer health insurance system on Stacks blockchain

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-MEMBER-NOT-FOUND (err u102))
(define-constant ERR-CLAIM-NOT-FOUND (err u103))
(define-constant ERR-MINIMUM-CONTRIBUTION (err u104))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u105))
(define-constant ERR-MEMBER-ALREADY-EXISTS (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-CLAIM-LIMIT-EXCEEDED (err u108))
(define-constant ERR-INSUFFICIENT-BALANCE (err u109))
(define-constant ERR-SELF-REFERRAL (err u110))
(define-constant ERR-REFERRER-NOT-ACTIVE (err u111))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var pool-balance uint u0)
(define-data-var total-members uint u0)
(define-data-var total-claims uint u0)
(define-data-var minimum-contribution uint u1000000) ;; 1 STX in microSTX
(define-data-var max-claim-amount uint u5000000) ;; 5 STX max claim
(define-data-var referral-reward-percentage uint u5) ;; 5% of contribution as reward

;; Data maps
(define-map members principal {
    contribution: uint,
    total-contributed: uint,
    claims-count: uint,
    last-claim-block: uint,
    is-active: bool
})

(define-map referral-stats principal {
    referrals-made: uint,
    total-rewards-earned: uint,
    unclaimed-rewards: uint
})

(define-map claims uint {
    member: principal,
    amount: uint,
    evidence-hash: (string-ascii 64),
    status: (string-ascii 10), ;; "pending", "approved", "rejected"
    submitted-at: uint,
    processed-at: (optional uint),
    processor: (optional principal)
})

;; Emergency pause functionality
(define-data-var is-paused bool false)

;; Member management functions
(define-public (join-pool (contribution uint) (referrer (optional principal)))
    (let (
        (sender tx-sender)
        (reward-amount (/ (* contribution (var-get referral-reward-percentage)) u100))
    )
        (asserts! (not (var-get is-paused)) ERR-NOT-AUTHORIZED)
        (asserts! (>= contribution (var-get minimum-contribution)) ERR-MINIMUM-CONTRIBUTION)
        (asserts! (is-none (map-get? members sender)) ERR-MEMBER-ALREADY-EXISTS)
        
        (match referrer
            referrer-principal
            (begin
                (asserts! (not (is-eq referrer-principal sender)) ERR-SELF-REFERRAL)
                (let ((referrer-data (unwrap! (map-get? members referrer-principal) ERR-MEMBER-NOT-FOUND)))
                    (asserts! (get is-active referrer-data) ERR-REFERRER-NOT-ACTIVE)
                    (let ((referrer-stats (default-to { referrals-made: u0, total-rewards-earned: u0, unclaimed-rewards: u0 } (map-get? referral-stats referrer-principal))))
                        (map-set referral-stats referrer-principal {
                            referrals-made: (+ (get referrals-made referrer-stats) u1),
                            total-rewards-earned: (+ (get total-rewards-earned referrer-stats) reward-amount),
                            unclaimed-rewards: (+ (get unclaimed-rewards referrer-stats) reward-amount)
                        })
                    )
                )
            )
            true
        )
        
        (try! (stx-transfer? contribution sender (as-contract tx-sender)))
        
        (map-set members sender {
            contribution: contribution,
            total-contributed: contribution,
            claims-count: u0,
            last-claim-block: u0,
            is-active: true
        })
        
        (var-set pool-balance (+ (var-get pool-balance) contribution))
        (var-set total-members (+ (var-get total-members) u1))
        
        (ok true)
    )
)

(define-public (contribute-additional (amount uint))
    (let ((sender tx-sender)
          (member-data (unwrap! (map-get? members sender) ERR-MEMBER-NOT-FOUND)))
        (asserts! (not (var-get is-paused)) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (get is-active member-data) ERR-MEMBER-NOT-FOUND)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount sender (as-contract tx-sender)))
        
        ;; Update member data
        (map-set members sender (merge member-data {
            contribution: (+ (get contribution member-data) amount),
            total-contributed: (+ (get total-contributed member-data) amount)
        }))
        
        ;; Update pool balance
        (var-set pool-balance (+ (var-get pool-balance) amount))
        
        (ok true)
    )
)

;; Claim management functions
(define-public (submit-claim (amount uint) (evidence-hash (string-ascii 64)))
    (let ((sender tx-sender)
          (claim-id (+ (var-get total-claims) u1))
          (member-data (unwrap! (map-get? members sender) ERR-MEMBER-NOT-FOUND)))
        (asserts! (not (var-get is-paused)) ERR-NOT-AUTHORIZED)
        (asserts! (get is-active member-data) ERR-MEMBER-NOT-FOUND)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount (var-get max-claim-amount)) ERR-CLAIM-LIMIT-EXCEEDED)
        (asserts! (<= amount (var-get pool-balance)) ERR-INSUFFICIENT-BALANCE)
        
        ;; Create claim
        (map-set claims claim-id {
            member: sender,
            amount: amount,
            evidence-hash: evidence-hash,
            status: "pending",
            submitted-at: stacks-block-height,
            processed-at: none,
            processor: none
        })
        
        ;; Update member claims count
        (map-set members sender (merge member-data {
            claims-count: (+ (get claims-count member-data) u1),
            last-claim-block: stacks-block-height
        }))
        
        ;; Update total claims
        (var-set total-claims claim-id)
        
        (ok claim-id)
    )
)

(define-public (approve-claim (claim-id uint))
    (let ((claim-data (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status claim-data) "pending") ERR-CLAIM-ALREADY-PROCESSED)
        (asserts! (<= (get amount claim-data) (var-get pool-balance)) ERR-INSUFFICIENT-BALANCE)
        
        ;; Transfer funds to member
        (try! (as-contract (stx-transfer? (get amount claim-data) tx-sender (get member claim-data))))
        
        ;; Update claim status
        (map-set claims claim-id (merge claim-data {
            status: "approved",
            processed-at: (some stacks-block-height),
            processor: (some tx-sender)
        }))
        
        ;; Update pool balance
        (var-set pool-balance (- (var-get pool-balance) (get amount claim-data)))
        
        (ok true)
    )
)

(define-public (reject-claim (claim-id uint))
    (let ((claim-data (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status claim-data) "pending") ERR-CLAIM-ALREADY-PROCESSED)
        
        ;; Update claim status
        (map-set claims claim-id (merge claim-data {
            status: "rejected",
            processed-at: (some stacks-block-height),
            processor: (some tx-sender)
        }))
        
        (ok true)
    )
)

;; Admin functions
(define-public (set-minimum-contribution (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (var-set minimum-contribution amount)
        (ok true)
    )
)

(define-public (set-max-claim-amount (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (var-set max-claim-amount amount)
        (ok true)
    )
)

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set is-paused true)
        (ok true)
    )
)

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set is-paused false)
        (ok true)
    )
)

(define-public (deactivate-member (member principal))
    (let ((member-data (unwrap! (map-get? members member) ERR-MEMBER-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set members member (merge member-data { is-active: false }))
        (ok true)
    )
)

(define-public (claim-referral-rewards)
    (let (
        (sender tx-sender)
        (referrer-stats (unwrap! (map-get? referral-stats sender) ERR-MEMBER-NOT-FOUND))
        (reward-amount (get unclaimed-rewards referrer-stats))
    )
        (asserts! (not (var-get is-paused)) ERR-NOT-AUTHORIZED)
        (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= reward-amount (var-get pool-balance)) ERR-INSUFFICIENT-BALANCE)
        
        (try! (as-contract (stx-transfer? reward-amount tx-sender sender)))
        
        (map-set referral-stats sender (merge referrer-stats {
            unclaimed-rewards: u0
        }))
        
        (var-set pool-balance (- (var-get pool-balance) reward-amount))
        
        (ok reward-amount)
    )
)

(define-public (set-referral-reward-percentage (percentage uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= percentage u100) ERR-INVALID-AMOUNT)
        (var-set referral-reward-percentage percentage)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-pool-balance)
    (var-get pool-balance)
)

(define-read-only (get-total-members)
    (var-get total-members)
)

(define-read-only (get-total-claims)
    (var-get total-claims)
)

(define-read-only (get-member-data (member principal))
    (map-get? members member)
)

(define-read-only (get-claim-data (claim-id uint))
    (map-get? claims claim-id)
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (get-minimum-contribution)
    (var-get minimum-contribution)
)

(define-read-only (get-max-claim-amount)
    (var-get max-claim-amount)
)

(define-read-only (is-contract-paused)
    (var-get is-paused)
)

(define-read-only (get-referral-stats (member principal))
    (map-get? referral-stats member)
)

(define-read-only (get-referral-reward-percentage)
    (var-get referral-reward-percentage)
)

(define-read-only (get-pool-stats)
    {
        balance: (var-get pool-balance),
        total-members: (var-get total-members),
        total-claims: (var-get total-claims),
        min-contribution: (var-get minimum-contribution),
        max-claim: (var-get max-claim-amount),
        is-paused: (var-get is-paused)
    }
)
