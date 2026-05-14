#!/usr/bin/env bash
# setup-deps.sh — Install Foundry dependencies for ClearPact contracts.
# Run once after cloning on any machine with forge installed.
# Idempotent: forge install is a no-op if the lib already exists.

set -euo pipefail

cd "$(dirname "$0")"

echo "→ Installing OpenZeppelin Contracts (v5.x)..."
forge install OpenZeppelin/openzeppelin-contracts --no-commit

echo "→ Installing OpenZeppelin Contracts Upgradeable (v5.x)..."
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

echo "✓ Dependencies installed. Run 'forge build' to verify."
