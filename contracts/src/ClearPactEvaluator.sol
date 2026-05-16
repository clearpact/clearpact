// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// What this contract owns: ClearPactEvaluator — thin wrapper that forwards evaluation actions
//   (approve/dispute resolution) to a ClearPactJob contract on behalf of authorised evaluators.
//   Provides an auditable on-chain evaluator registry and access-controlled dispatch.
// What it does NOT own: job lifecycle logic, fee calculation, token handling, hook callbacks,
//   storage of job state. All of that belongs to ClearPactJob.

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable}          from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IClearPactJob}            from "./interfaces/IClearPactJob.sol";

/// @title ClearPactEvaluator
/// @notice Thin router contract: authorised evaluators call approveResult / rejectResult here
///         and this contract forwards to the target ClearPactJob. Provides a unified audit trail
///         of every evaluator action across all job contracts via EvaluatorApproved / EvaluatorRejected
///         events.
/// @dev Phase 3 + P8 fix. Inherits AccessControlUpgradeable + UUPSUpgradeable.
///      EVALUATOR_ROLE is required to call either forwarding function.
contract ClearPactEvaluator is
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    // ─── Roles ──────────────────────────────────────────────────────────────

    /// @notice Role for addresses permitted to evaluate jobs.
    bytes32 public constant EVALUATOR_ROLE = keccak256("EVALUATOR_ROLE");

    // ─── Custom Errors ───────────────────────────────────────────────────────

    error NotEvaluator();
    error ZeroAddress();

    // ─── Events ──────────────────────────────────────────────────────────────

    /// @notice Emitted when an evaluator successfully approves a job result.
    event EvaluatorApproved(
        address indexed jobContract,
        uint256 indexed jobId,
        address indexed evaluator,
        bytes32         reason
    );

    /// @notice Emitted when an evaluator rejects a job result. P8 fix: renamed from DisputeResolved.
    event EvaluatorRejected(
        address indexed jobContract,
        uint256 indexed jobId,
        address indexed evaluator,
        bytes32         reason
    );

    // ─── Storage gap ─────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Initializer ─────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the evaluator registry. Call once via proxy.
    /// @param admin Initial DEFAULT_ADMIN_ROLE holder; also granted EVALUATOR_ROLE.
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EVALUATOR_ROLE,     admin);
    }

    // ─── UUPS Authorization ──────────────────────────────────────────────────

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ─── Evaluation Actions ───────────────────────────────────────────────────

    /// @notice Approve a submitted result and trigger payment settlement.
    /// @dev Forwards to IClearPactJob.complete. Caller must hold EVALUATOR_ROLE.
    ///      reason is forwarded verbatim to the job contract and also emitted here
    ///      for the cross-contract audit trail.
    /// @param jobContract Address of the ClearPactJob proxy.
    /// @param jobId       Job to approve.
    /// @param reason      Arbitrary bytes32 reason code (ABI-encoded or hash).
    function approveResult(
        address jobContract,
        uint256 jobId,
        bytes32 reason
    ) external {
        if (!hasRole(EVALUATOR_ROLE, msg.sender)) revert NotEvaluator();
        if (jobContract == address(0)) revert ZeroAddress();

        // Forward to ClearPactJob.complete — no optParams needed from evaluator path.
        IClearPactJob(jobContract).complete(jobId, reason, "");

        emit EvaluatorApproved(jobContract, jobId, msg.sender, reason);
    }

    /// @notice Reject a submitted result on behalf of an evaluator.
    /// @dev Forwards to IClearPactJob.reject. Caller must hold EVALUATOR_ROLE.
    /// @param jobContract Address of the ClearPactJob proxy.
    /// @param jobId       Job to reject.
    /// @param reason      Rejection reason code.
    function rejectResult(
        address jobContract,
        uint256 jobId,
        bytes32 reason
    ) external {
        if (!hasRole(EVALUATOR_ROLE, msg.sender)) revert NotEvaluator();
        if (jobContract == address(0)) revert ZeroAddress();

        IClearPactJob(jobContract).reject(jobId, reason, "");

        emit EvaluatorRejected(jobContract, jobId, msg.sender, reason);  // P8 fix: renamed from DisputeResolved
    }

    // ─── ERC-165 ─────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
