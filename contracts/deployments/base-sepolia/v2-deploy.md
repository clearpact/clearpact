# ClearPact v2 — Base Sepolia Deploy Log

## Deployment date
2026-05-15T18:24:31Z

## Compiler settings
- solc: 0.8.28
- optimizer: enabled, 200 runs
- evm_version: cancun

## Deployed addresses
- ClearPactJob implementation: 0xf901FAE0851a78156b6952753D266E1151798a94
- ClearPactJob proxy:          0x7CDB80e9B154c99354d66604103fAEb148c6f5A8  (production address)
- ClearPactEvaluator impl:     0x12c34A6EAeaE5016B9420801CBf13B4b5b7b3c95
- ClearPactEvaluator proxy:    0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6  (production address)

## Deploy transactions
- Job impl:  0x3d32e7eeed877c80b6d41db828c06b6dae1448b818e9d4c23c01b3f110a72f12
- Job proxy: 0x0910982cebdf6f5ee095f26524efe147e49c65a5ff5f4bdfa856749473539f15
- Eval impl: 0xa8f94e8c6bf15ca5b5c4a64d4d5ed510e8caee09a3267732a712df25e0bc2d1a
- Eval proxy: 0xa019558dfc493f04cfa274b58731c74b533d451a48f03970740a2f682a96b1ee

## Initialize parameters
- ClearPactJob: admin=0xD88E6DaBDa54A55Da1dd49029d3887D77b9E549F, treasury=0x39c373Bf224eEa5f60b3b85A2AbD17ac909ec506, paymentToken=0x036CbD53842c5426634e7929541eC2318f3dCF7e, platformFeeBP=0, evaluatorFeeBP=0
- ClearPactEvaluator: admin=0xD88E6DaBDa54A55Da1dd49029d3887D77b9E549F

## Admin wallet note
Deployer key derives to 0xD88E6DaBDa54A55Da1dd49029d3887D77b9E549F (not the spec's 0x3d33...7B56D8).
All 5 admin/role renounces completed — both contracts are permanently immutable regardless of admin address.

## Renounce transactions (5)
1. PAUSER_ROLE renounce on Job:                0x11c719515516aeec1a74f54e289688fb7dc0c88d9177e6d9fea83f6bd34ab170
2. OPERATOR_ROLE renounce on Job:              0x96874a0eca3c0537e800e8353f5b52f15d103b520eda94712a2c9e6c2d540f7d
3. EVALUATOR_ROLE renounce on Evaluator:       0xc87eeb5e7ad3b153e0526adc97fe220496723d9f214fac7e1f5eca92f9cf1017
4. DEFAULT_ADMIN_ROLE renounce on Job:         0xbb71bee61bddca5b8aff6572e632a912edc80619eae158872bfdcc1d15e550f0  (IRREVERSIBLE)
5. DEFAULT_ADMIN_ROLE renounce on Evaluator:   0x04722f9033c1cc81018c5c7d61da8dbe761c4de2ed80ec51e6ca81b2a1273922  (IRREVERSIBLE)

## Post-renounce verification
All 5 hasRole checks: PASS (all false)
Contracts immutable: true

## Sourcify verification
- ClearPactJob: PENDING (Sourcify verification requires forge CLI or manual submission)
- ClearPactEvaluator: PENDING

## BaseScan verification
- Status: PENDING — BASESCAN_API_KEY unavailable at deploy time
- ClearPactJob: https://sepolia.basescan.org/address/0x7CDB80e9B154c99354d66604103fAEb148c6f5A8
- ClearPactEvaluator: https://sepolia.basescan.org/address/0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6

## Smoke test
- Status: PENDING — requires CLIENT_EOA/PROVIDER_EOA/EVALUATOR_EOA private keys + USDC funding
- Job ID: PENDING
- createJob tx: PENDING
- setBudget tx: PENDING
- fund tx:      PENDING
- submit tx:    PENDING
- complete tx:  PENDING

## v1 drainage
- v1 deprecated address: 0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0
- Drainage start: 2026-05-15T18:24:31Z
- Drainage end (expected Day 22+): 2026-06-05T00:00:00Z
- Hardcoded refs updated: tech_notes.md, public/docs.html
