// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// What this interface owns: ClearPact-specific extension getters and custom errors beyond the
//   ERC-8183 spec surface. Provides access to per-job metadata not in the spec Job struct.
// What it does NOT own: core lifecycle functions, admin functions, standard events, hook callbacks.

/// @title IClearPactExtensions
/// @notice ClearPact-specific extensions beyond the EIP-8183 base interface.
/// @dev Implemented alongside IClearPactJob. Does NOT duplicate any spec function or event.
interface IClearPactExtensions {

    // ─── Extension Getters ────────────────────────────────────────────────────

    /// @notice Retrieve the condition reference hash for a job.
    function getJobConditionRef(uint256 jobId) external view returns (bytes32);

    /// @notice Retrieve the payment token address for a job.
    function getJobToken(uint256 jobId) external view returns (address);

    /// @notice Retrieve ClearPact-specific timestamps for a job.
    function getJobTimestamps(uint256 jobId) external view returns (uint256 createdAt, uint256 fundedAt, uint256 settledAt);

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error OnlyClient();
    error OnlyProvider();
    error OnlyEvaluator();
    error WrongState();
    error BudgetZero();
    error ProviderNotSet();
    error NotExpired();
}
