# ClearPact Technical Notes

## Contract Verification: ClearPactEscrow.sol

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
