# ClearPactEscrow

On-chain escrow for conditional USDC payments on [Base](https://base.org).
A payer locks USDC, a designated settler (or the contract owner) releases the
funds to the payee once off-chain conditions have been met, and refunds are
available before settlement.

The hosted API, SDK, and dashboard that wrap this contract are at
**[clearpact.polsia.app](https://clearpact.polsia.app)**.
This repository contains **only** the Solidity source, ABI, and Foundry
profile — the operational tooling lives in a separate, private repository.

## Status

| Network       | Address                                                                                                                                                              | Status                          |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| Base Sepolia  | [`0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`](https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0) | Live (testnet)                  |
| Base Mainnet  | TBD                                                                                                                                                                  | Pending deployer wallet funding |

The Sepolia deployment is verified on Sourcify (partial match — see
[`tech_notes.md`](tech_notes.md) for details and BaseScan verification steps).

The contract has **not** been audited. Use at your own risk.
There are currently **no Solidity tests** in this repository — add a Foundry
test suite before relying on it for anything beyond experimentation.

## Layout

```
contracts/ClearPactEscrow.sol   Solidity source (pragma ^0.8.20)
abi/ClearPactEscrow.json        Pre-built ABI for off-chain integrations
foundry.toml                    Foundry profile pinned to deployed settings
tech_notes.md                   Compiler settings, Sourcify status, BaseScan steps
```

## Build

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge build
```

The profile pins `solc 0.8.28+commit.7893614a`, optimizer enabled (200 runs),
`evm_version = cancun` — the exact settings of the deployed Sepolia bytecode.

## Test

```bash
forge test
```

(No tests yet — `test/` directory is intentionally absent.)

## Contract overview

`ClearPactEscrow` tracks escrows through six states:

| Value | State                  | Meaning                                      |
| ----: | ---------------------- | -------------------------------------------- |
|   0   | `PendingFunding`       | Created, awaiting payer deposit              |
|   1   | `Funded`               | USDC deposited in the contract               |
|   2   | `AwaitingVerification` | Conditions being checked off-chain           |
|   3   | `Settled`              | Funds released to payee                      |
|   4   | `Refunded`             | Funds returned to payer                      |
|   5   | `Cancelled`            | Cancelled before funding                     |

Settlement is performed by an authorized settler address or the contract
owner. A future revision will add an ERC-8004 validator adapter so that
settlement can be triggered automatically by a verifier contract.

## ABI

For integrators without a Solidity toolchain, the ABI is committed at
[`abi/ClearPactEscrow.json`](abi/ClearPactEscrow.json) and is included in the
published npm tarball.

## License

[MIT](LICENSE)
