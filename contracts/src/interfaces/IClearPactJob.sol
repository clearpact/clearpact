// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// What this interface owns: ERC-8183 full ABI surface — Job struct, JobStatus enum, 8 core
//   lifecycle functions, 3 admin functions, 1 view function, 12 standard events, 2 custom events.
// What it does NOT own: implementation logic, storage layout, access control, token handling,
//   ClearPact extension getters (see IClearPactExtensions.sol).

/// @title IClearPactJob
/// @notice ERC-8183 compliant interface for programmable job escrow.
/// @dev Verbatim transcription of the EIP-8183 specification. Every function selector and event
///      topic0 hash must binary-match the spec for automatic indexer compatibility.
interface IClearPactJob {

    // ─── Enums ──────────────────────────────────────────────────────────────

    /// @notice Lifecycle state of a job — exact ERC-8183 spec values.
    enum JobStatus {
        Open,       // 0
        Funded,     // 1
        Submitted,  // 2
        Completed,  // 3
        Rejected,   // 4
        Expired     // 5
    }

    // ─── Structs ────────────────────────────────────────────────────────────

    /// @notice Canonical 9-field storage struct — exact ERC-8183 spec field order.
    struct Job {
        uint256   id;
        address   client;
        address   provider;
        address   evaluator;
        string    description;
        uint256   budget;
        uint256   expiredAt;
        JobStatus status;
        address   hook;
    }

    // ─── Core Lifecycle Functions (8) ────────────────────────────────────────

    /// @notice Create a new job. Client is msg.sender.
    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external returns (uint256 jobId);

    /// @notice Set or change the provider for an Open job.
    function setProvider(uint256 jobId, address provider_) external;

    /// @notice Set or override the budget (and optionally the token) for a job.
    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external;

    /// @notice Fund an existing job (transfer tokens into escrow).
    function fund(uint256 jobId, bytes calldata optParams) external;

    /// @notice Provider submits a deliverable for evaluation.
    function submit(uint256 jobId, bytes32 deliverable, bytes calldata optParams) external;

    /// @notice Evaluator approves and completes the job.
    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    /// @notice Evaluator or client rejects the submission.
    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    /// @notice Client claims a refund after expiry.
    function claimRefund(uint256 jobId) external;

    // ─── Admin Functions (3) ─────────────────────────────────────────────────

    /// @notice Update the platform fee rate and treasury address.
    function setPlatformFee(uint256 feeBP_, address treasury_) external;

    /// @notice Update the evaluator fee rate.
    function setEvaluatorFee(uint256 feeBP_) external;

    /// @notice Whitelist or de-whitelist a hook contract.
    function setHookWhitelist(address hook, bool status) external;

    // ─── View Functions (1) ───────────────────────────────────────────────────

    /// @notice Read the full state of a job.
    function getJob(uint256 jobId) external view returns (Job memory);

    // ─── Standard ERC-8183 Events (12) ───────────────────────────────────────

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed provider,
        address evaluator,
        uint256 expiredAt,
        address hook
    );

    event ProviderSet(uint256 indexed jobId, address indexed provider);

    event BudgetSet(uint256 indexed jobId, uint256 amount);

    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);

    event JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable);

    event JobCompleted(uint256 indexed jobId, address indexed evaluator, bytes32 reason);

    event JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason);

    event JobExpired(uint256 indexed jobId);

    event PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount);

    event EvaluatorFeePaid(uint256 indexed jobId, address indexed evaluator, uint256 amount);

    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);

    event HookWhitelistUpdated(address indexed hook, bool status);

    // ─── ClearPact-Specific Custom Events (2) ────────────────────────────────

    /// @notice Emitted by createJob in addition to JobCreated, carrying ClearPact metadata.
    event ClearPactJobMetadata(uint256 indexed jobId, bytes32 conditionRef, string description);

    /// @notice Emitted by setBudget when optParams contains a token override.
    event ClearPactJobTokenSet(uint256 indexed jobId, address indexed token);
}
