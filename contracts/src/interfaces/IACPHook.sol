// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// What this interface owns: ERC-8183 hook callback surface — beforeAction and afterAction.
// What it does NOT own: hook registration, job state, fee logic, token transfers, or magic values.

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IACPHook
/// @notice ERC-8183 hook callback interface. Inherits IERC165 for supportsInterface validation.
/// @dev Implementations are validated via IERC165.supportsInterface(type(IACPHook).interfaceId).
///      Exactly 2 functions: beforeAction and afterAction. No magic return values.
interface IACPHook is IERC165 {

    /// @notice Called before a lifecycle action executes on a job.
    /// @param jobId    The job being acted upon.
    /// @param selector The bytes4 selector of the lifecycle function being called.
    /// @param data     ABI-encoded action-specific context.
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;

    /// @notice Called after a lifecycle action executes on a job.
    /// @param jobId    The job that was acted upon.
    /// @param selector The bytes4 selector of the lifecycle function that was called.
    /// @param data     ABI-encoded action-specific context.
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
