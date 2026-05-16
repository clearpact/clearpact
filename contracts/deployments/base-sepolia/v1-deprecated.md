# ClearPact v1 — Base Sepolia Deprecation

## Status
DEPRECATED as of 2026-05-15. New escrow creation redirected to v2.

## v1 Contract Address
`0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0`

## Network
Base Sepolia (Chain ID 84532)

## Explorer
https://sepolia.basescan.org/address/0xe1E45CD17FdEe0C38b011FDDA25B259B26140DB0

## Why deprecated
- Does not implement ERC-8183 standard
- No UUPS upgradeability
- No access control roles
- No hook system
- No fee split
- No evaluator flow

## v1 → v2 migration
- New `createJob` calls: use v2 proxy (see v2-deploy.md for address)
- Existing v1 escrows: settle naturally per their `expiredAt`
- v1 drainage period: 7 days from deprecation date (2026-05-15 to 2026-06-05)
- v1 drainage audit: Day 22+ (Phase 5, owner-side)

## Do not interact with v1 after drainage
The v1 contract has no admin functions to disable it. Existing funded escrows can still
be settled by their authorizedSettler. After all v1 escrows have settled or expired,
the contract is effectively dormant. No further action is required on-chain.
