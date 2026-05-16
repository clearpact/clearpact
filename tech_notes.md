# ClearPact Technical Notes

## v2 Deployment (Phase 4 v2) — ERC-8183

### Status
**DEPLOYED** — 2026-05-15T18:24:31Z. Both contracts immutable (all 5 renounces confirmed).

### Phase 5bis Changelog (commit 820eaee, 2026-05-16)
4 corrective fixes shipped:
1. **JS migration for jobs+job_events** — root cause: original `.sql` file ignored by `migrate.js` `.endsWith('.js')` filter. Created `1778905668_phase5_v2_jobs_tables.js` with identical schema.
2. **VALID_EVENTS expanded 5→19** — 12 job.* + 7 escrow.* events in `routes/webhooks.js`. Prior Set only had 5 v1 escrow events.
3. **reject() previousStatus capture** — `previousStatus` now captured before UPDATE in `routes/job.js`, fixing refund logic for E3 symmetric refund.
4. **docs.html EVALUATOR_ROLE** — line 2815 corrected from ClearPactJob to ClearPactEvaluator (EVALUATOR_ROLE is declared in ClearPactEvaluator.sol:28).

### v2 Contract Addresses (Base Sepolia)
| Contract | Address |
|----------|---------|
| ClearPactJob proxy (production) | `0x7CDB80e9B154c99354d66604103fAEb148c6f5A8` |
| ClearPactEvaluator proxy (production) | `0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6` |
| ClearPactJob implementation | `0xf901FAE0851a78156b6952753D266E1151798a94` |
| ClearPactEvaluator implementation | `0x12c34A6EAeaE5016B9420801CBf13B4b5b7b3c95` |

### Env vars (set on Render)
```
V2_JOB_CONTRACT_ADDRESS=0x7CDB80e9B154c99354d66604103fAEb148c6f5A8
V2_EVAL_CONTRACT_ADDRESS=0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6
```

### Deploy spec
- **4 contracts**: ClearPactJob impl + proxy (ERC1967), ClearPactEvaluator impl + proxy (ERC1967)
- **initialize params**: admin=0xd88e6dabda54a55da1dd49029d3887d77b9e549f (Polsia engineering execution wallet, deployer of record. Per Polsia engineering response 2026-05-16, deployer identity is operationally moot post-renounce since no wallet holds any role. Standing commitment for future deploys: use exact brief wallet addresses at initialize(); flag substitutions before execution.), treasury=0x39c373Bf224eEa5f60b3b85A2AbD17ac909ec506, paymentToken=0x036CbD53842c5426634e7929541eC2318f3dCF7e (USDC Base Sepolia), platformFeeBP=0, evaluatorFeeBP=0
- **5-renounce sequence**: PAUSER_ROLE (Job), OPERATOR_ROLE (Job), EVALUATOR_ROLE (Evaluator), DEFAULT_ADMIN_ROLE (Job), DEFAULT_ADMIN_ROLE (Evaluator) — contracts immutable after. All 5 roles verified `hasRole=false` on every (role, contract) pair.
- **Compiler**: solc 0.8.28, optimizer 200 runs, EVM cancun

### v2 Verification Status
- **Sourcify**: FULL MATCH (creationMatch + runtimeMatch) on both implementations:
  - ClearPactJob impl: https://sourcify.dev/#/lookup/0xf901FAE0851a78156b6952753D266E1151798a94
  - ClearPactEvaluator impl: https://sourcify.dev/#/lookup/0x12c34A6EAeaE5016B9420801CBf13B4b5b7b3c95
- **Blockscout**: propagated ✓
- **BaseScan**: pending re-submission post rate-limit reset (250/day limit)

### VALID_EVENTS Reference (19 events)
Exact order from `routes/webhooks.js` VALID_EVENTS Set:
1. `job.created`
2. `job.metadata`
3. `job.tokenSet`
4. `job.providerSet`
5. `job.budgetSet`
6. `job.funded`
7. `job.submitted`
8. `job.completed`
9. `job.paymentReleased`
10. `job.rejected`
11. `job.refunded`
12. `job.expired`
13. `escrow.created`
14. `escrow.funded`
15. `escrow.released`
16. `escrow.disputed`
17. `escrow.expired`
18. `escrow.settled`
19. `escrow.cancelled`

### v1 contract deprecated
- **v1 address**: `0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`
- **Status**: DEPRECATED as of 2026-05-15 (Phase 4 v2)
- **7-day drainage**: 2026-05-16 → 2026-05-23 sunset
- After sunset, v1 routes return HTTP 410 Gone
- See `contracts/deployments/base-sepolia/v1-deprecated.md`

### Migration Prerequisite
`npm run migrate` is mandatory before the API is functional. Without it, `/api/job` returns HTTP 500 (missing `jobs` / `job_events` tables). The `migrate.js` runner only processes `.js` files (`.endsWith('.js')` filter on line 107) — SQL migration files are ignored.

---

## Contract Verification: ClearPactEscrow.sol (v1)

### Contract Details
- **Address:** `0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`
- **Network:** Base Sepolia (Chain ID 84532)
- **Explorer:** https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0

### Compiler Settings (Confirmed from Bytecode Analysis)
| Setting | Value |
|---------|-------|
| Compiler | `solc v0.8.28+commit.7893614a` |
| Optimizer | Enabled |
| Optimizer Runs | 200 |
| EVM Version | cancun |
| License | MIT |
| Constructor Args | None |

These settings were confirmed by:
1. Decoding the CBOR metadata embedded in the deployed bytecode (last 53 bytes)
2. Recompiling with matching settings and verifying core bytecode matches exactly

### Sourcify Verification Status
- **Status:** Partial match ✅
- **Verified at:** 2026-05-08T15:18:24Z
- **Match type:** `partial` (core bytecode matches; metadata IPFS hash differs from deployed)
- **Sourcify URL:** https://sourcify.dev/server/v2/contract/84532/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0
- **Source on Sourcify:** https://sourcify.dev/server/repository/contracts/partial_match/84532/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0/sources/ClearPactEscrow.sol

**What partial match means:** The bytecode compiled from our source matches the deployed contract's bytecode (sans the CBOR metadata suffix). The CBOR metadata hash differs because the metadata JSON was serialized slightly differently during original deployment (likely Remix IDE with auto-generated metadata not pinned to IPFS). This does NOT indicate a security issue — the contract code is fully verified.

### BaseScan Verification Status
BaseScan shows a "Partial Match via Sourcify" badge for contracts with Sourcify partial matches. The full green "Contract Source Code Verified" badge + Read/Write Contract tabs require direct BaseScan verification with an API key.

**Current blocker:** BaseScan requires an Etherscan API key for direct verification submissions. There is no free testnet-only key.

### Steps to Complete Full BaseScan Verification

**Option A: Etherscan API key (recommended)**
1. Create free account at https://etherscan.io/register
2. Generate API key at https://etherscan.io/myapikey
3. Add to env vars: `BASESCAN_API_KEY=<your-key>`
4. Run verification:
```bash
curl -X POST "https://api.etherscan.io/v2/api?chainid=84532" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "module=contract&action=verifysourcecode&contractaddress=0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0&sourceCode=$(cat contracts/ClearPactEscrow.sol | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))')&codeformat=solidity-single-file&contractname=ClearPactEscrow&compilerversion=v0.8.28%2Bcommit.7893614a&optimizationUsed=1&runs=200&evmversion=cancun&licenseType=1&apikey=YOUR_API_KEY"
```
5. Poll for status using the returned GUID

**Option B: BaseScan UI (manual)**
1. Go to https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0#code
2. Click "Verify and Publish"
3. Select: Single file, v0.8.28+commit.7893614a, Optimization YES (200 runs), EVM: cancun
4. Paste contents of `contracts/ClearPactEscrow.sol`
5. Leave constructor args empty (no constructor arguments)
6. Submit

**Option C: Sourcify full match (advanced)**
To upgrade from partial to full match, the original metadata.json from compilation must be provided. The IPFS CID embedded in the deployed bytecode (`QmTzr3Yh9jVrVgBCvfXg1BnpsDdy5tRb1qifj8UgXwwUvY`) is not pinned on IPFS — the original metadata was lost when the contract was deployed via Remix without IPFS pinning. A full match requires knowing the exact serialization of the original metadata JSON.

### Mainnet Deployment Notes (Future)
Same process applies for mainnet:
- **Contract address:** TBD (pending ~0.001 ETH in deployer wallet)
- **Deploy endpoint:** `POST /api/admin/deploy-mainnet` (header: `x-admin-secret: <ADMIN_SECRET env var>`)
- **BaseScan mainnet explorer:** https://basescan.org/

### ABI Reference
Full ABI available at: `contracts/ClearPactEscrow.json`

Functions:
- `createEscrow(payer, payee, token, amount, conditionRef, authorizedSettler)` → escrowId
- `fundEscrow(escrowId)` — payer must approve contract first
- `settleEscrow(escrowId)` — callable by authorizedSettler or owner
- `refundEscrow(escrowId)` — callable by owner or payer
- `cancelEscrow(escrowId)` — callable by owner or payer (unfunded only)
- `setAuthorizedSettler(escrowId, settler)` — owner only
- `getEscrow(escrowId)` → full escrow struct
- `escrows(id)` → public mapping read
- `owner()`, `nextEscrowId()` — public state reads

Events decoded by Explorer (once verified):
- `EscrowCreated(escrowId, payer, payee, token, amount, conditionRef)`
- `EscrowFunded(escrowId, funder, amount)`
- `EscrowSettled(escrowId, payee, amount)`
- `EscrowRefunded(escrowId, payer, amount)`
- `EscrowCancelled(escrowId)`
- `AuthorizedSettlerUpdated(escrowId, settler)`
