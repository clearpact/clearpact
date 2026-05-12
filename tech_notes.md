# Technical notes

## Contract details

| Field           | Value                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------- |
| Address         | `0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`                                                       |
| Network         | Base Sepolia (chain ID `84532`)                                                                    |
| Explorer        | https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0                    |
| Sourcify        | https://sourcify.dev/server/v2/contract/84532/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0           |
| Match type      | `partial` (core bytecode matches, metadata IPFS hash differs)                                      |
| License         | MIT                                                                                                |

## Compiler settings (confirmed against deployed bytecode)

| Setting          | Value                            |
| ---------------- | -------------------------------- |
| Compiler         | `solc v0.8.28+commit.7893614a`   |
| Optimizer        | enabled                          |
| Optimizer runs   | 200                              |
| EVM version      | `cancun`                         |
| Constructor args | none                             |

These settings were validated by decoding the CBOR metadata embedded in the
last 53 bytes of the deployed bytecode and recompiling locally for a
byte-for-byte match. They are pinned in [`foundry.toml`](foundry.toml).

## Build with Foundry

```bash
forge build
```

To produce a flattened single-file source (useful for the BaseScan UI):

```bash
forge flatten contracts/ClearPactEscrow.sol > flattened.sol
```

## What "partial match" means on Sourcify

The bytecode compiled from this repository matches the deployed contract's
bytecode **except for the CBOR metadata suffix**. The metadata's IPFS hash
differs because the metadata JSON was serialized slightly differently during
the original deployment. This is **not** a security issue — the executable
code is identical. Sourcify still shows the source as fully readable, and
BaseScan surfaces a *"Partial Match via Sourcify"* badge.

A *full match* would require the exact original `metadata.json` from
compilation, which was not preserved.

## BaseScan verification (manual UI flow)

1. Go to
   https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0#code
2. Click **Verify and Publish**.
3. Settings:
   - Compiler Type: **Solidity (Single file)**
   - Compiler Version: `v0.8.28+commit.7893614a`
   - Open Source License Type: **MIT**
4. Optimization:
   - Enabled: **Yes**
   - Runs: **200**
5. EVM version: **cancun**
6. Paste the contents of `contracts/ClearPactEscrow.sol`
   (or the output of `forge flatten` if the verifier expects a single file).
7. Constructor arguments: leave empty (the contract has none).
8. Submit.

If you have an Etherscan API key, you can submit the same payload through
the v2 API at `https://api.etherscan.io/v2/api?chainid=84532`
(`module=contract&action=verifysourcecode&...`). The form fields map 1:1 to
the UI options above.

## Contract surface

Functions:

- `createEscrow(payer, payee, token, amount, conditionRef, authorizedSettler) → escrowId`
- `fundEscrow(escrowId)` — payer must `approve` the contract first
- `settleEscrow(escrowId)` — callable by `authorizedSettler` or owner
- `refundEscrow(escrowId)` — callable by owner or payer
- `cancelEscrow(escrowId)` — callable by owner or payer (unfunded only)
- `setAuthorizedSettler(escrowId, settler)` — owner only
- `getEscrow(escrowId) → Escrow`
- `escrows(id)` — public mapping read
- `owner()`, `nextEscrowId()` — public state reads

Events:

- `EscrowCreated(escrowId, payer, payee, token, amount, conditionRef)`
- `EscrowFunded(escrowId, funder, amount)`
- `EscrowSettled(escrowId, payee, amount)`
- `EscrowRefunded(escrowId, payer, amount)`
- `EscrowCancelled(escrowId)`
- `AuthorizedSettlerUpdated(escrowId, settler)`

## Mainnet

A Base mainnet deployment is planned. The address is not yet known — this
file and the `README.md` Status table will be updated once the deployer
wallet is funded and the contract is published.
