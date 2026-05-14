# ClearPact Contracts

On-chain escrow primitives for conditional payments on [Base](https://base.org).
Two contracts coexist in this repository: the **v1 single-purpose escrow**
currently deployed on Base Sepolia, and the **v2 ERC-8183 compliant
programmable job escrow** being prepared for public deployment.

The hosted API, SDK, and dashboard that wrap these contracts are at
**[clearpact.polsia.app](https://clearpact.polsia.app)**.
This repository contains **only** the Solidity sources, ABIs, and Foundry
profile. The operational tooling (API, indexer, settlement worker) lives in
a separate, private repository.

## Repository purpose

This repository exists for **transparency on the Solidity code** that backs
the [clearpact.polsia.app](https://clearpact.polsia.app) product. It allows
anyone to:

- Read the source of the escrow contract that holds funds on testnet today
  (`contracts/ClearPactEscrow.sol`).
- Read the source of the upcoming ERC-8183 implementation
  (`contracts/src/ClearPactJob.sol`) and the interfaces it conforms to.
- Reproduce the build locally with Foundry and verify the bytecode against
  the deployed contract on Sourcify / BaseScan.

It is **not** a packaged SDK, nor a production toolkit. There are currently
**no Solidity tests** in this repository — add a Foundry test suite before
relying on either contract for anything beyond experimentation. **The
contracts have not been audited.**

## Repository layout

```
contracts/
├── ClearPactEscrow.sol         # v1 — deployed on Base Sepolia
├── ClearPactEscrow.json        # v1 ABI
├── foundry.toml                # Compiler + remappings
├── foundry.lock                # Pinned dependency versions
├── setup-deps.sh               # `forge install` helper for OZ deps
├── .gitignore                  # Ignore foundry build artifacts
├── lib/                        # (gitignored) populated by setup-deps.sh
└── src/
    ├── ClearPactJob.sol        # v2 — ERC-8183 compliant
    └── interfaces/
        ├── IClearPactJob.sol         # ERC-8183 core surface
        ├── IClearPactExtensions.sol  # ClearPact-specific view extensions
        └── IACPHook.sol              # Hook interface (ERC-8183)

LICENSE                         # MIT
README.md                       # this file
tech_notes.md                   # Verification details (Sourcify, BaseScan)
.gitmodules                     # OpenZeppelin upgradeable as submodule
```

## Contracts

### v1 — `ClearPactEscrow.sol` (legacy, live on Sepolia)

Single-purpose escrow contract. A payer locks USDC, a designated settler
(or the contract owner) releases the funds to the payee once off-chain
conditions have been met, and refunds are available before settlement.

| Network       | Address                                                                                                                       | Status                          |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| Base Sepolia  | [`0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`](https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0) | Live (testnet)                  |
| Base Mainnet  | TBD                                                                                                                            | Pending deployer wallet funding |

The Sepolia deployment is verified on Sourcify (partial match — see
[`tech_notes.md`](tech_notes.md) for verification details, including the
BaseScan UI flow and an Etherscan v2 API recipe).

**Functions** (entry points used by the off-chain settlement worker):

- `createEscrow(payer, payee, token, amount, conditionRef, authorizedSettler) → escrowId`
- `fundEscrow(escrowId)` — payer must `approve` the contract first
- `settleEscrow(escrowId)` — callable by `authorizedSettler` or owner
- `refundEscrow(escrowId)` — owner or payer
- `cancelEscrow(escrowId)` — owner or payer, unfunded only
- `setAuthorizedSettler(escrowId, settler)` — owner only
- `getEscrow(escrowId) → Escrow`, `escrows(id)`, `owner()`, `nextEscrowId()` — views

### v2 — `ClearPactJob.sol` (active development, ERC-8183 compliant)

Programmable job escrow conforming to the [ERC-8183 "Agentic Commerce
Protocol"](https://eips.ethereum.org/EIPS/eip-8183) draft standard. Where
v1 is a single-flow escrow tied to ClearPact's off-chain settlement worker,
v2 exposes the full ERC-8183 surface (12 functions, 12 standard events,
hook integration) and is designed to be upgradeable and composable.

**Inheritance chain** (OpenZeppelin v5 upgradeable):

```
ClearPactJob
├── UUPSUpgradeable
├── AccessControlUpgradeable
├── PausableUpgradeable
├── ReentrancyGuardTransient     (Cancun transient storage)
├── IClearPactJob                (ERC-8183 surface)
└── IClearPactExtensions         (ClearPact-specific views)
```

**Status**: implementation compiled clean. Public deployment to Base
Sepolia and verification on BaseScan / Sourcify are planned next. The
`ClearPactEvaluator.sol` wrapper (Phase 3) and Foundry test suite are not
yet in this repository.

**ERC-8183 conformance**: the 12 selectors of `ClearPactJob` are a
byte-for-byte match against the ERC-8183 reference specification. The
contract additionally exposes ClearPact-specific extensions (per-job
payment token override, condition reference hashes) via
`IClearPactExtensions`.

For background on the design choices behind the v1 → v2 transition, see the
public engineering brief at
[valkenberg.net/engineering-brief-clearpact-v2-native-refactor-for-erc-8183-abi-compliance](https://www.valkenberg.net/engineering-brief-clearpact-v2-native-refactor-for-erc-8183-abi-compliance/).

## Build

The contracts use Foundry. Install dependencies first, then build.

```bash
# 1. Install dependencies (OpenZeppelin contracts + upgradeable)
bash contracts/setup-deps.sh

# 2. Build
cd contracts
forge build
```

`setup-deps.sh` runs `forge install` for both OZ libraries. It is
idempotent. The `.gitmodules` file declares
`openzeppelin-contracts-upgradeable` as a submodule for users who prefer
`git submodule update --init`; the regular `openzeppelin-contracts` is
fetched via `forge install`.

The exact versions used by Polsia for the v2 build are pinned in
`contracts/foundry.lock` (OpenZeppelin Contracts Upgradeable v5.6.1,
commit `7bf4727aacdbfaa0f36cbd664654d0c9e1dc52bf`).

To produce a flattened single-file source (useful for BaseScan UI
verification of v1):

```bash
forge flatten contracts/ClearPactEscrow.sol > flattened.sol
```

## Verification (v1)

See [`tech_notes.md`](tech_notes.md) for:

- Compiler settings confirmed against the deployed bytecode
  (solc 0.8.28, optimizer 200 runs, EVM cancun).
- What Sourcify's "partial match" status means (core bytecode matches; CBOR
  metadata hash differs).
- The BaseScan UI verification flow.
- An Etherscan v2 API verification recipe.
- The IPFS CID of the original (lost) compilation metadata.

## Security

- These contracts have **not** undergone a third-party audit.
- There are **no Solidity tests** in this repository at this stage. A
  Foundry test suite is on the roadmap.
- The v2 `ClearPactJob.sol` is **upgradeable (UUPS)**: a holder of
  `DEFAULT_ADMIN_ROLE` can replace the implementation. The role transfer
  policy for the public deployment will be documented at deploy time.
- Use the testnet deployment for experimentation only.

## License

[MIT](LICENSE) — © 2026 ClearPact.
