// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// What this contract owns: ERC-8183 ClearPactJob core implementation — job lifecycle, fee
//   distribution, hook integration, UUPS upgradeability, access control, pause logic.
// What it does NOT own: hook implementations (IACPHook), escrow indexing (off-chain),
//   legacy ClearPactEscrow.sol flows, token price logic, dispute arbitration.

import {UUPSUpgradeable}         from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable}      from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20}                from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20}                   from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165}                  from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IClearPactJob}        from "./interfaces/IClearPactJob.sol";
import {IClearPactExtensions} from "./interfaces/IClearPactExtensions.sol";
import {IACPHook}             from "./interfaces/IACPHook.sol";

/// @title ClearPactJob
/// @notice ERC-8183 compliant programmable job escrow. UUPS upgradeable.
/// @dev Phase 2bis of the ERC-8183 ABI compliance refactor. Inherits all four OZ upgradeable
///      base contracts plus the two ClearPact interfaces. ReentrancyGuardTransient uses
///      Cancun transient storage (no storage slot conflicts with UUPS layout).
contract ClearPactJob is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    IClearPactJob,
    IClearPactExtensions
{
    using SafeERC20 for IERC20;

    // ─── Roles ──────────────────────────────────────────────────────────────

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ─── Storage ────────────────────────────────────────────────────────────

    /// @dev ERC-8183 spec: 9-field Job struct keyed by jobId.
    mapping(uint256 => Job) private _jobs;

    /// @dev Per-job payment token override. address(0) = use default token.
    mapping(uint256 => address) private _jobTokens;

    /// @dev ClearPact-specific condition reference hash per job.
    mapping(uint256 => bytes32) private _jobConditionRefs;

    /// @dev Timestamp when a job was created (block.timestamp at createJob).
    mapping(uint256 => uint256) private _jobCreatedAt;

    /// @dev Timestamp when a job was funded (block.timestamp at fund).
    mapping(uint256 => uint256) private _jobFundedAt;

    /// @dev Timestamp when a job was settled (block.timestamp at complete/claimRefund).
    mapping(uint256 => uint256) private _jobSettledAt;

    /// @dev Auto-incrementing job ID counter. Starts at 1.
    uint256 private _jobCounter;

    /// @notice Platform fee in basis points (100 BP = 1%). Max 10_000.
    uint256 public platformFeeBP;

    /// @notice Address that receives platform fees.
    address public treasury;

    /// @notice Evaluator fee in basis points (100 BP = 1%). Max 10_000.
    uint256 public evaluatorFeeBP;

    /// @notice Whitelisted hook addresses that may receive callbacks.
    mapping(address => bool) public whitelistedHooks;

    // E2 fix: global default payment token. Used by _resolveToken when no per-job override is set.
    /// @notice Global default payment token (e.g. USDC). Set at initialize; overrideable per-job via setBudget.
    address public paymentToken;

    /// @dev UUPS upgrade safety gap. Reduced from [50] to [49] to accommodate paymentToken slot (E2 fix).
    uint256[49] private __gap;

    // ─── Constants ──────────────────────────────────────────────────────────

    /// @dev Maximum combined fee: platform + evaluator must not exceed 50% (5000 BP).
    uint256 private constant MAX_FEE_BP = 5_000;

    /// @dev Gas cap for hook callbacks. Silent fail if hook exceeds this.
    uint256 private constant HOOK_GAS_CAP = 100_000;

    // ─── Custom Events (admin) ───────────────────────────────────────────────

    event PlatformFeeUpdated(uint256 feeBP, address treasury);
    event EvaluatorFeeUpdated(uint256 feeBP);

    // ─── Initializer ────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract. Call once via proxy deployment.
    /// @param admin           Address granted DEFAULT_ADMIN_ROLE.
    /// @param treasury_       Address that receives platform fees.
    /// @param paymentToken_   Global default payment token (e.g. USDC on Base). E2 fix.
    /// @param platformFeeBP_  Initial platform fee in basis points.
    /// @param evaluatorFeeBP_ Initial evaluator fee in basis points.
    function initialize(
        address admin,
        address treasury_,
        address paymentToken_,
        uint256 platformFeeBP_,
        uint256 evaluatorFeeBP_
    ) external initializer {
        require(admin          != address(0), "admin = zero");
        require(treasury_      != address(0), "treasury = zero");
        require(paymentToken_  != address(0), "paymentToken = zero");  // E2 fix
        require(platformFeeBP_ + evaluatorFeeBP_ <= MAX_FEE_BP, "fees exceed 50%");

        // UUPSUpgradeable (OZ v5) has no __init function — it is storage-free.
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE,     admin);
        _grantRole(PAUSER_ROLE,       admin);

        treasury       = treasury_;
        paymentToken   = paymentToken_;           // E2 fix
        platformFeeBP  = platformFeeBP_;
        evaluatorFeeBP = evaluatorFeeBP_;
    }

    // ─── UUPS Authorization ─────────────────────────────────────────────────

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ─── Core Lifecycle Functions ────────────────────────────────────────────

    /// @inheritdoc IClearPactJob
    /// @dev 5 positional args — no struct. Emits JobCreated (6 params) + ClearPactJobMetadata.
    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external override nonReentrant whenNotPaused returns (uint256 jobId) {
        require(expiredAt > block.timestamp, "expiredAt in past");
        // hook address(0) is allowed (no hook). Non-zero hooks must be whitelisted.
        if (hook != address(0)) {
            require(whitelistedHooks[hook], "hook not whitelisted");
            require(
                IERC165(hook).supportsInterface(type(IACPHook).interfaceId),
                "hook: bad interfaceId"
            );
        }

        unchecked { jobId = ++_jobCounter; }

        _jobs[jobId] = Job({
            id:          jobId,
            client:      msg.sender,
            provider:    provider,
            evaluator:   evaluator,
            description: description,
            budget:      0,
            expiredAt:   expiredAt,
            status:      JobStatus.Open,
            hook:        hook
        });

        _jobCreatedAt[jobId] = block.timestamp;

        // Standard 6-param ERC-8183 event (no description in spec event).
        emit JobCreated(jobId, msg.sender, provider, evaluator, expiredAt, hook);
        // ClearPact-specific: description + conditionRef (zero until setBudget sets it).
        emit ClearPactJobMetadata(jobId, bytes32(0), description);
    }

    /// @inheritdoc IClearPactJob
    function setProvider(
        uint256 jobId,
        address provider_
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState(); // job doesn't exist
        if (msg.sender != job.client) revert OnlyClient();
        if (job.status != JobStatus.Open) revert WrongState();

        job.provider = provider_;
        emit ProviderSet(jobId, provider_);
    }

    /// @inheritdoc IClearPactJob
    /// @dev Core spec function. optParams may ABI-encode (address token, bytes32 conditionRef).
    ///      If token != address(0), emits ClearPactJobTokenSet. conditionRef stored in extension.
    ///      E1 fix: re-emits ClearPactJobMetadata when conditionRef is non-zero so event-only
    ///      indexers see the real conditionRef (createJob always emits conditionRef=0).
    function setBudget(
        uint256 jobId,
        uint256 amount,
        bytes calldata optParams
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();
        if (msg.sender != job.client) revert OnlyClient();
        if (job.status != JobStatus.Open) revert WrongState();
        if (amount == 0) revert BudgetZero();

        job.budget = amount;

        // Decode optional params: (address token, bytes32 conditionRef).
        if (optParams.length >= 32) {
            address tokenOverride = abi.decode(optParams[:32], (address));
            if (tokenOverride != address(0)) {
                _jobTokens[jobId] = tokenOverride;
                emit ClearPactJobTokenSet(jobId, tokenOverride);
            }
        }
        if (optParams.length >= 64) {
            (, bytes32 conditionRef) = abi.decode(optParams[:64], (address, bytes32));
            if (conditionRef != bytes32(0)) {
                _jobConditionRefs[jobId] = conditionRef;
                // E1 fix: re-emit with real conditionRef so indexers don't see conditionRef=0.
                emit ClearPactJobMetadata(jobId, conditionRef, job.description);
            }
        }

        emit BudgetSet(jobId, amount);
    }

    /// @inheritdoc IClearPactJob
    function fund(
        uint256 jobId,
        bytes calldata optParams
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();
        if (msg.sender != job.client) revert OnlyClient();
        if (job.status != JobStatus.Open) revert WrongState();
        if (job.budget == 0) revert BudgetZero();
        if (job.provider == address(0)) revert ProviderNotSet();

        address token = _resolveToken(jobId);

        bytes4 sel = IClearPactJob.fund.selector;
        _callBeforeHook(jobId, sel, optParams, job.hook);

        // Transfer tokens from client into this contract (escrow).
        IERC20(token).safeTransferFrom(msg.sender, address(this), job.budget);

        job.status = JobStatus.Funded;
        _jobFundedAt[jobId] = block.timestamp;

        emit JobFunded(jobId, msg.sender, job.budget);

        _callAfterHook(jobId, sel, optParams, job.hook);
    }

    /// @inheritdoc IClearPactJob
    function submit(
        uint256 jobId,
        bytes32 deliverable,
        bytes calldata optParams
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();
        if (msg.sender != job.provider) revert OnlyProvider();
        if (job.status != JobStatus.Funded) revert WrongState();

        bytes4 sel = IClearPactJob.submit.selector;
        _callBeforeHook(jobId, sel, optParams, job.hook);

        job.status = JobStatus.Submitted;

        emit JobSubmitted(jobId, msg.sender, deliverable);

        _callAfterHook(jobId, sel, optParams, job.hook);
    }

    /// @inheritdoc IClearPactJob
    /// @dev Triggers fee split + settlement. Evaluator or client may call.
    function complete(
        uint256 jobId,
        bytes32 reason,
        bytes calldata optParams
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();
        if (msg.sender != job.evaluator && msg.sender != job.client) revert OnlyEvaluator();
        if (job.status != JobStatus.Submitted) revert WrongState();

        bytes4 sel = IClearPactJob.complete.selector;
        _callBeforeHook(jobId, sel, optParams, job.hook);

        job.status = JobStatus.Completed;
        _jobSettledAt[jobId] = block.timestamp;

        // Fee split and settlement.
        address token  = _resolveToken(jobId);
        uint256 total  = job.budget;
        uint256 pfee   = (total * platformFeeBP)  / 10_000;
        uint256 efee   = (total * evaluatorFeeBP) / 10_000;
        uint256 payout = total - pfee - efee;

        if (pfee > 0 && treasury != address(0)) {
            IERC20(token).safeTransfer(treasury, pfee);
        }
        if (efee > 0 && job.evaluator != address(0)) {
            IERC20(token).safeTransfer(job.evaluator, efee);
            emit EvaluatorFeePaid(jobId, job.evaluator, efee);
        }
        IERC20(token).safeTransfer(job.provider, payout);

        emit JobCompleted(jobId, msg.sender, reason);
        emit PaymentReleased(jobId, job.provider, payout);

        _callAfterHook(jobId, sel, optParams, job.hook);
    }

    /// @inheritdoc IClearPactJob
    /// @dev E3 fix: 3 lifecycle paths supported.
    ///      Open → Rejected:      client only (pre-funding cancel, no token transfer).
    ///      Funded → Rejected:    evaluator only (pre-submission reject, automatic refund).
    ///      Submitted → Rejected: evaluator OR client (post-submission reject, automatic refund).
    ///      Symmetric refund: both Funded and Submitted paths refund full budget to client.
    function reject(
        uint256 jobId,
        bytes32 reason,
        bytes calldata optParams
    ) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();

        JobStatus s = job.status;
        // E3 fix: 3 lifecycle paths with correct ACL.
        if (s == JobStatus.Open) {
            // Pre-funding cancel: client only.
            if (msg.sender != job.client) revert OnlyClient();
        } else if (s == JobStatus.Funded) {
            // Pre-submission reject: evaluator only.
            if (msg.sender != job.evaluator) revert OnlyEvaluator();
        } else if (s == JobStatus.Submitted) {
            // Post-submission reject: evaluator OR client.
            if (msg.sender != job.evaluator && msg.sender != job.client) revert OnlyEvaluator();
        } else {
            revert WrongState();
        }

        bytes4 sel = IClearPactJob.reject.selector;
        _callBeforeHook(jobId, sel, optParams, job.hook);

        // State transition BEFORE safeTransfer (checks-effects-interactions).
        job.status = JobStatus.Rejected;

        // E3 fix: symmetric automatic refund when funds are escrowed (Funded or Submitted).
        if (s == JobStatus.Funded || s == JobStatus.Submitted) {
            uint256 amount = job.budget;
            address token  = _resolveToken(jobId);
            _jobSettledAt[jobId] = block.timestamp;
            IERC20(token).safeTransfer(job.client, amount);
            emit Refunded(jobId, job.client, amount);
        }

        emit JobRejected(jobId, msg.sender, reason);

        _callAfterHook(jobId, sel, optParams, job.hook);
    }

    /// @inheritdoc IClearPactJob
    /// @dev Explicitly non-hookable per spec. Client only, after expiredAt.
    function claimRefund(uint256 jobId) external override nonReentrant whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.client == address(0)) revert WrongState();
        if (msg.sender != job.client) revert OnlyClient();
        // Only Funded or Submitted jobs have escrowed funds.
        if (job.status != JobStatus.Funded && job.status != JobStatus.Submitted) revert WrongState();
        if (block.timestamp <= job.expiredAt) revert NotExpired();

        uint256 amount = job.budget;
        address token  = _resolveToken(jobId);

        job.status = JobStatus.Expired;
        _jobSettledAt[jobId] = block.timestamp;

        IERC20(token).safeTransfer(job.client, amount);

        emit JobExpired(jobId);
        emit Refunded(jobId, job.client, amount);
        // No hook calls — claimRefund is explicitly non-hookable.
    }

    // ─── Admin Functions ─────────────────────────────────────────────────────

    /// @inheritdoc IClearPactJob
    function setPlatformFee(
        uint256 feeBP_,
        address treasury_
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feeBP_ + evaluatorFeeBP <= MAX_FEE_BP, "fees exceed 50%");
        require(treasury_ != address(0), "treasury = zero");
        platformFeeBP = feeBP_;
        treasury      = treasury_;
        emit PlatformFeeUpdated(feeBP_, treasury_);
    }

    /// @inheritdoc IClearPactJob
    function setEvaluatorFee(
        uint256 feeBP_
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(platformFeeBP + feeBP_ <= MAX_FEE_BP, "fees exceed 50%");
        evaluatorFeeBP = feeBP_;
        emit EvaluatorFeeUpdated(feeBP_);
    }

    /// @inheritdoc IClearPactJob
    function setHookWhitelist(
        address hook,
        bool status
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistedHooks[hook] = status;
        emit HookWhitelistUpdated(hook, status);
    }

    // ─── Pause (PAUSER_ROLE) ─────────────────────────────────────────────────

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @inheritdoc IClearPactJob
    function getJob(uint256 jobId) external view override returns (Job memory) {
        return _jobs[jobId];
    }

    // ─── Extension Getters (IClearPactExtensions) ─────────────────────────────

    /// @inheritdoc IClearPactExtensions
    function getJobConditionRef(uint256 jobId) external view override returns (bytes32) {
        return _jobConditionRefs[jobId];
    }

    /// @inheritdoc IClearPactExtensions
    function getJobToken(uint256 jobId) external view override returns (address) {
        return _jobTokens[jobId];
    }

    /// @inheritdoc IClearPactExtensions
    function getJobTimestamps(uint256 jobId)
        external
        view
        override
        returns (uint256 createdAt, uint256 fundedAt, uint256 settledAt)
    {
        return (_jobCreatedAt[jobId], _jobFundedAt[jobId], _jobSettledAt[jobId]);
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    /// @dev Resolve the token for a job: per-job override, then global default paymentToken.
    ///      E2 fix: falls back to paymentToken when no per-job override is set.
    ///      Reverts if neither is configured.
    function _resolveToken(uint256 jobId) internal view returns (address token) {
        token = _jobTokens[jobId];
        if (token == address(0)) {
            token = paymentToken;  // E2 fix: fallback to global default
        }
        require(token != address(0), "no token configured");
    }

    /// @dev Call hook.beforeAction with a 100k gas cap. Silent fail on revert.
    ///      Only fires when hook != address(0) and hook is whitelisted.
    function _callBeforeHook(
        uint256 jobId,
        bytes4  selector,
        bytes calldata data,
        address hook
    ) internal {
        if (hook == address(0) || !whitelistedHooks[hook]) return;
        // 100k gas cap — try/catch for silent fail.
        try IACPHook(hook).beforeAction{gas: HOOK_GAS_CAP}(jobId, selector, data) {}
        catch {}
    }

    /// @dev Call hook.afterAction with a 100k gas cap. Silent fail on revert.
    function _callAfterHook(
        uint256 jobId,
        bytes4  selector,
        bytes calldata data,
        address hook
    ) internal {
        if (hook == address(0) || !whitelistedHooks[hook]) return;
        try IACPHook(hook).afterAction{gas: HOOK_GAS_CAP}(jobId, selector, data) {}
        catch {}
    }

    // ─── ERC-165 ──────────────────────────────────────────────────────────────

    /// @dev Overrides to support IClearPactJob + IClearPactExtensions + AccessControl.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IClearPactJob).interfaceId         ||
            interfaceId == type(IClearPactExtensions).interfaceId  ||
            super.supportsInterface(interfaceId);
    }
}
