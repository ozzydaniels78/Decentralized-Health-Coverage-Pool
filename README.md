# 🏥 Decentralized Health Coverage Pool 

A peer-pooled micro-health coverage system built on Stacks blockchain using Clarity smart contracts.

## 🎯 Features

- Member contribution management
- Claim submission and processing
- Transparent fund management
- Admin-controlled claim verification

## 💡 How It Works

1. **Join the Pool**: Members join by contributing a minimum of 1M microSTX
2. **Submit Claims**: Members can submit health-related claims with evidence
3. **Claim Processing**: Admin reviews and approves/rejects claims
4. **Automatic Payouts**: Approved claims trigger automatic STX transfers

## 🚀 Usage

### For Members

```clarity
;; Join the pool
(contract-call? .health-pool join-pool u1000000)

;; Submit a claim
(contract-call? .health-pool submit-claim u500000 "hospital-receipt-hash")

;; Check your member data
(contract-call? .health-pool get-member-data tx-sender)
```

### For Administrators

```clarity
;; Process claims
(contract-call? .health-pool approve-claim u1)
(contract-call? .health-pool reject-claim u2)

;; Check pool status
(contract-call? .health-pool get-pool-balance)
(contract-call? .health-pool get-total-members)
```

## 🔒 Security

- Minimum contribution threshold
- Admin-only claim approval
- Balance checks for all transfers
- Member verification for claims

## 📈 Future Enhancements

- DAO governance implementation
- Multi-signature claim approval
- Tiered coverage plans
- Automated claim verification via oracles
```
