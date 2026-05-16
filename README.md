# ClearPact

**Programmable payment layer for AI agents.** Stablecoin escrow, conditional settlement, ERC-8004 validation, all on-chain.

> "Machines pay machines. ClearPact enforces the terms."

Live: [clearpact.polsia.app](https://clearpact.polsia.app) · [API Docs](https://clearpact.polsia.app/docs)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                    ClearPact Stack (Phase 2)                     │
│                                                                  │
│  ┌─────────────────┐   ┌──────────────────────────────────────┐ │
│  │  REST API        │   │  ERC-8004 Validation Adapter         │ │
│  │  (Express.js)    │   │  services/erc8004-adapter.js         │ │
│  │                  │   │                                      │ │
│  │  POST /api/escrow│   │  • Accepts validation signals via    │ │
│  │  GET  /api/escrow│   │    POST /api/validation/submit       │ │
│  │  POST /api/      │   │  • Finds matching escrow by          │ │
│  │    validation/   │   │    external_job_id                   │ │
│  │    submit        │   │  • Checks settlement eligibility     │ │
│  └────────┬─────────┘   │  • Calls on-chain settleEscrow()    │ │
│           │             │  • Replay protection built-in        │ │
│           │             │  • In-process polling (5s interval)  │ │
│           ▼             └──────────────────┬─────────────────┘ │
│  ┌─────────────────┐                       │                    │
│  │  PostgreSQL      │◄──────────────────────┘                   │
│  │  (Neon)          │   validation_records + escrows tables     │
│  └────────┬─────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ClearPactEscrow.sol — Base Sepolia (Chain ID: 84532)    │   │
│  │  USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e        │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

**Request flow:**

1. Client calls `POST /api/escrow` with `external_job_id` → escrow created on-chain + DB
2. Client funds escrow: `POST /api/escrow/:id/fund`
3. Validator (oracle) submits proof: `POST /api/validation/submit`
4. ERC-8004 adapter processes signal → calls `settleOnchainEscrow()` → payee receives USDC
5. Client polls `GET /api/escrow/:id` to observe settled state + tx hashes

---

## Contract Design

**File:** `contracts/ClearPactEscrow.json` (ABI + bytecode)

### Key Functions

| Function | Who Calls | Description |
|----------|-----------|-------------|
| `createEscrow(payer, payee, token, amount, conditionRef, authorizedSettler)` | API | Lock escrow on-chain |
| `fundEscrow(escrowId)` | Payer | Transfer USDC into contract |
| `settleEscrow(escrowId)` | Adapter (authorizedSettler) | Release USDC to payee |
| `refundEscrow(escrowId)` | API | Return USDC to payer |
| `cancelEscrow(escrowId)` | API | Cancel unfunded escrow |
| `getEscrow(escrowId)` | Anyone | Read on-chain state |

### Escrow States (on-chain enum)

| Index | State | Description |
|-------|-------|-------------|
| 0 | `pending_funding` | Created, awaiting deposit |
| 1 | `funded` | USDC deposited |
| 2 | `awaiting_verification` | Funds held, waiting for proof |
| 3 | `settled` | USDC released to payee |
| 4 | `refunded` | USDC returned to payer |
| 5 | `cancelled` | Cancelled before funding |

### ERC-8004 Linkage

The contract's `conditionRef` field stores a keccak256 hash of the escrow conditions. The `authorizedSettler` field is set to the deployer wallet (adapter signer), ensuring only the verified ERC-8004 settlement path can call `settleEscrow()`.

---

## ERC-8004 Adapter: What's Real, What's Stubbed

### What is REAL

- Validation signals are stored in PostgreSQL (`validation_records` table) with replay protection
- The adapter finds the matching escrow by `external_job_id` → `verification_reference` column
- When `result = 'success'`, the adapter calls `blockchain.settleOnchainEscrow()` on the real Base Sepolia contract
- The payee's on-chain wallet receives actual USDC on Base Sepolia
- Every settlement is traceable: `validation_record.settle_tx_hash` + `escrow.settle_tx_hash` + BaseScan link
- Replay protection is enforced at two levels:
  1. DB: `UNIQUE(external_job_id, proof_hash)` — same signal cannot be inserted twice
  2. Logic: escrow status checked before settlement — already-settled escrows are rejected
- In-process polling worker runs every 5 seconds without a separate process

### What is STUBBED

- **The validation source**: In this MVP, signals are submitted via `POST /api/validation/submit` (API call). In production, this would be replaced by an **on-chain event listener** watching a deployed ERC-8004 Validation Registry contract for `ValidationRecordCreated` events.
- **Confirmation threshold**: We wait for 2 blocks on testnet. Mainnet should use ≥12.
- **The ERC-8004 Registry contract itself**: No separate registry contract is deployed. The MVP uses the API as a simulated registry.

### ERC-8004 Concept (for context)

ERC-8004 proposes a standardized on-chain registry where validator nodes attest that a job (identified by `externalJobId`) has been completed. The settlement adapter watches this registry and triggers escrow settlement when a matching proof is found.

Conceptual registry interface:

```solidity
interface IERC8004Registry {
    function submitProof(
        bytes32 externalJobId,
        bytes32 proofHash,
        bool success
    ) external;

    function getProof(bytes32 externalJobId)
        external view
        returns (bool exists, bool success, bytes32 proofHash);

    event ValidationRecordCreated(
        bytes32 indexed externalJobId,
        bytes32 proofHash,
        bool success
    );
}
```

### What Remains for Productionization

1. **Deploy ERC-8004 Registry contract** on Base mainnet
2. **Replace API polling with on-chain event listener**:
   ```js
   registry.on('ValidationRecordCreated', async (jobId, proofHash, success) => {
     await adapter.processOnchainValidation({ jobId, proofHash, success });
   });
   ```
3. **Increase `MIN_CONFIRMATIONS` to 12** for mainnet reorg safety
4. **Move to BullMQ** for durable background processing (current: in-process setInterval)
5. **Multi-sig authorized settler** for production security

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string (Neon) |

### Blockchain (Optional — enables on-chain mode)

| Variable | Description |
|----------|-------------|
| `DEPLOYER_PRIVATE_KEY` | Wallet private key for contract interactions |
| `ESCROW_CONTRACT_ADDRESS` | Deployed ClearPactEscrow contract address |
| `BASE_SEPOLIA_RPC_URL` | RPC endpoint (default: `https://sepolia.base.org`) |

> Without blockchain vars, the app runs in **graceful degradation mode**: all API endpoints work, blockchain operations return `null`, settlement is recorded in DB only.

---

## Deployment Steps

### 1. Prerequisites

```bash
# Install dependencies
npm install

# Ensure PostgreSQL is accessible (DATABASE_URL set)
npm run migrate
```

### 2. Smart Contract Deployment

```bash
# Fund deployer wallet with Base Sepolia ETH
# Get test ETH from: https://www.alchemy.com/faucets/base-sepolia

# Set environment variable
export DEPLOYER_PRIVATE_KEY=<your_wallet_private_key>

# Deploy contract
node scripts/deploy-contract.js
# Output: Contract address + TX hash

# Set the contract address
export ESCROW_CONTRACT_ADDRESS=<output_from_above>
```

### 3. Start Server

```bash
npm start
```

The ERC-8004 settlement worker starts automatically with the server.

---

## Testnet Setup

### Base Sepolia Details

| Field | Value |
|-------|-------|
| Chain ID | 84532 |
| RPC URL | `https://sepolia.base.org` |
| Explorer | `https://sepolia.basescan.org` |
| USDC Contract | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

### Get Test ETH

1. Visit [Alchemy Base Sepolia Faucet](https://www.alchemy.com/faucets/base-sepolia)
2. Enter deployer wallet address: `0xf7dac097dfDeD6316587A19fCAD4eF4b572F3798`
3. Request 0.1 ETH (sufficient for many transactions)

### Get Test USDC

USDC on Base Sepolia is Circle's official test contract. Acquire it from:
- [Circle Faucet](https://faucet.circle.com/) — select "Base Sepolia"

---

## Demo Flow Walkthrough

Run the complete end-to-end demo:

```bash
# Against the live API
node scripts/demo-e2e.js https://clearpact.polsia.app

# Against a local server
node scripts/demo-e2e.js http://localhost:3000
```

The demo script automates the full flow without any undocumented manual steps:

```
Step 0: Health check               verify server is live
Step 1: Create API key             get credentials
Step 2: Create escrow              POST /api/escrow with external_job_id
Step 3: Read on-chain state        GET /api/escrow/:id
Step 4: Fund escrow                POST /api/escrow/:id/fund
Step 5: Submit ERC-8004 signal     POST /api/validation/submit
Step 6: Watch automatic settlement poll GET /api/escrow/:id
Step 7: Final state + tx hashes    full audit trail
Step 8: Explorer links             BaseScan URLs
```

### Manual Demo (curl)

```bash
BASE=https://clearpact.polsia.app

# 1. Create key
KEY=$(curl -s -X POST $BASE/api/keys \
  -H "Content-Type: application/json" \
  -d '{"email":"test@demo.dev","name":"demo"}' | jq -r .key)

# 2. Create escrow with external_job_id
ESCROW_ID=$(curl -s -X POST $BASE/api/escrow \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $KEY" \
  -d '{
    "payer": "0xf7dac097dfDeD6316587A19fCAD4eF4b572F3798",
    "payee": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "amount": 10,
    "external_job_id": "my-job-001"
  }' | jq -r .escrow.id)

# 3. Fund
curl -s -X POST $BASE/api/escrow/$ESCROW_ID/fund \
  -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
  -d '{}' | jq .escrow.status

# 4. Submit ERC-8004 validation (triggers automatic settlement)
curl -s -X POST $BASE/api/validation/submit \
  -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
  -d '{"external_job_id":"my-job-001","result":"success"}' | jq .

# 5. Check settlement after 10s
sleep 10
curl -s -H "X-API-Key: $KEY" $BASE/api/escrow/$ESCROW_ID \
  | jq '{status:.escrow.status, tx_hashes:.escrow.tx_hashes}'
```

---

## API Reference

### Escrow Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/escrow` | Key | Create escrow. Pass `external_job_id` for ERC-8004 linkage. |
| `GET` | `/api/escrow/:id` | Key | State + on-chain + events |
| `POST` | `/api/escrow/:id/fund` | Key | Record funding |
| `POST` | `/api/escrow/:id/cancel` | Key | Cancel or refund |
| `POST` | `/api/escrow/:id/settle` | Key | **DEPRECATED** — use `/api/validation/submit` |

### ERC-8004 Validation Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/validation/submit` | Key | Submit proof → auto-settlement |
| `GET` | `/api/validation/:id` | Key | Validation record status |
| `GET` | `/api/validation` | Key | List records (filter: `escrow_id`, `status`) |

### Key Management (public)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/keys` | Create API key |
| `GET` | `/api/keys?email=...` | List keys |
| `DELETE` | `/api/keys/:key_id` | Revoke key |
| `POST` | `/api/keys/:key_id/rotate` | Rotate key |

---

## Known Limitations

1. **No real ERC-8004 Registry contract**: Validation signals come via REST API, not on-chain events. Suitable for testnet/MVP.

2. **In-process worker**: The settlement poller runs as `setInterval` inside the Express process. For production durability, use BullMQ.

3. **Single authorized settler**: The deployer wallet is the sole authorized settler. Production should use multisig.

4. **Simulated mode**: Without `DEPLOYER_PRIVATE_KEY` and `ESCROW_CONTRACT_ADDRESS`, settlement is recorded in PostgreSQL but no on-chain transaction occurs.

5. **No USDC approval step**: Demo assumes payer has pre-approved the contract to spend USDC. In a real UX: `USDC.approve(contractAddress, amount)` must precede `fundEscrow()`.

---

## Project Structure

```
clearpact/
├── server.js                              # Express app + ERC-8004 worker startup
├── migrate.js                             # DB migration runner
├── routes/
│   ├── escrow.js                          # Escrow endpoints (Phase 2: external_job_id)
│   ├── validation.js                      # ERC-8004 validation endpoints
│   └── keys.js                            # API key management
├── services/
│   ├── blockchain.js                      # ethers.js wrapper for ClearPactEscrow
│   └── erc8004-adapter.js                 # Validation adapter + settlement worker
├── middleware/
│   └── auth.js                            # API key auth + rate limiting
├── contracts/
│   └── ClearPactEscrow.json               # Contract ABI + bytecode
├── migrations/
│   ├── 1744184000000_create_escrows.js
│   ├── 1744270000000_create_api_keys.js
│   ├── 1744350000000_add_blockchain_columns.js
│   └── 1744450000000_add_validation_records.js   # Phase 2
├── scripts/
│   ├── deploy-contract.js                 # Deploy to Base Sepolia
│   └── demo-e2e.js                        # End-to-end demo
└── public/
    ├── index.html                         # Landing page
    └── docs.html                          # Developer docs
```

---

## Phase Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Done | Smart contract on Base Sepolia, REST API, blockchain integration |
| Phase 2 | ✅ Done | ERC-8004 adapter, automatic settlement, demo script, README |
| Phase 3 | Planned | Real ERC-8004 on-chain registry listener, x402 facilitator |
| Phase 4 | Planned | Multi-party B2B settlement, fiat on-ramps |

---

*Built on Ethereum. Powered by Base Sepolia. Settlement enforced by code.*

---

## Public scope (2026-05-16)

This repository is the **public mirror** of the ClearPact v2 (ERC-8183) on-chain contracts and the official TypeScript/JavaScript SDK. It is intentionally minimalist — the operational backend that powers the hosted API at `clearpact.polsia.app` is **not** part of this mirror.

**Published here**:
- `contracts/src/` — Solidity sources (2 contracts + 3 interfaces)
- `contracts/deployments/` — v1 + v2 deploy notes
- `contracts/selectors-confirmation.txt` — 12 ERC-8183 function selectors verified binary-match
- `contracts/storage-layout-before.txt` / `-after.txt` — UUPS upgrade safety proof
- `sdk/` — official SDK (also published on npm as [`clearpact`](https://www.npmjs.com/package/clearpact))
- `tech_notes.md` — technical reference for the v2 deployment

**Use cases supported**:
- **Audit the deployed contracts**: read `contracts/src/`, cross-reference with [Sourcify FULL MATCH](https://sourcify.dev/#/lookup/0xf901FAE0851a78156b6952753D266E1151798a94) on both v2 implementations.
- **Integrate via SDK**: `npm install clearpact` + grab an API key at `clearpact.polsia.app/docs`. The SDK communicates with the hosted API over HTTPS — no self-host required.
- **Recompile locally** (advanced):
  ```bash
  cd contracts
  forge install OpenZeppelin/openzeppelin-contracts
  forge install OpenZeppelin/openzeppelin-contracts-upgradeable
  forge build
  ```
  The OpenZeppelin libraries are not vendored in this mirror — install them via `forge install`. Sourcify FULL MATCH on the deployed implementations guarantees the on-chain bytecode matches these sources.

**Not in scope here**: backend Express server, route handlers, webhook dispatcher, deploy operational scripts, dynamic frontend. The hosted instance is the supported integration path.

### Verifiable on-chain commitments (Base Sepolia, chain 84532)

- ClearPactJob proxy: `0x7CDB80e9B154c99354d66604103fAEb148c6f5A8` ([BaseScan](https://sepolia.basescan.org/address/0x7CDB80e9B154c99354d66604103fAEb148c6f5A8))
- ClearPactEvaluator proxy: `0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6` ([BaseScan](https://sepolia.basescan.org/address/0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6))
- 5-renounce sequence executed at deploy: `PAUSER_ROLE`, `OPERATOR_ROLE`, `EVALUATOR_ROLE`, `DEFAULT_ADMIN_ROLE × 2` contracts. `hasRole = false` on every (role, contract) pair, verifiable on-chain via any Base Sepolia RPC.
- Sourcify FULL MATCH (creationMatch + runtimeMatch) on both implementation contracts.

No admin can freeze the active contract, appoint evaluators, or upgrade the contract — verifiable on-chain.

The on-chain v2 contracts are immutable and verifiable:
- ClearPactJob proxy: `0x7CDB80e9B154c99354d66604103fAEb148c6f5A8` ([BaseScan](https://sepolia.basescan.org/address/0x7CDB80e9B154c99354d66604103fAEb148c6f5A8))
- ClearPactEvaluator proxy: `0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6` ([BaseScan](https://sepolia.basescan.org/address/0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6))
- Sourcify FULL MATCH on both implementations.

5-renounce sequence executed at Phase 4 v2 deploy. No admin can freeze the active contract, appoint evaluators, or upgrade the contract — verifiable on-chain.
