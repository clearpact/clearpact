// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ClearPactEscrow
 * @notice On-chain escrow for conditional USDC payments on Base Sepolia
 * @dev Phase 1: Manual settlement by authorized settler or owner.
 *      Phase 2 will add ERC-8004 adapter for automatic settlement.
 */

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract ClearPactEscrow {

    // ─── Status enum ────────────────────────────────────────────────
    enum Status {
        PendingFunding,       // 0 - Created, awaiting payer deposit
        Funded,               // 1 - Funds deposited in contract
        AwaitingVerification, // 2 - Conditions being verified off-chain
        Settled,              // 3 - Funds released to payee
        Refunded,             // 4 - Funds returned to payer
        Cancelled             // 5 - Cancelled before funding
    }

    // ─── Escrow struct ──────────────────────────────────────────────
    struct Escrow {
        address payer;
        address payee;
        address token;
        uint256 amount;
        Status  status;
        bytes32 conditionRef;        // Hash of off-chain condition set
        address authorizedSettler;   // Phase 2 ERC-8004 adapter address
        uint256 createdAt;
        uint256 fundedAt;
        uint256 settledAt;
    }

    // ─── State ──────────────────────────────────────────────────────
    uint256 public nextEscrowId;
    address public owner;
    mapping(uint256 => Escrow) public escrows;

    // ─── Events ─────────────────────────────────────────────────────
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed payer,
        address indexed payee,
        address token,
        uint256 amount,
        bytes32 conditionRef
    );
    event EscrowFunded(uint256 indexed escrowId, address indexed funder, uint256 amount);
    event EscrowSettled(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event EscrowCancelled(uint256 indexed escrowId);
    event AuthorizedSettlerUpdated(uint256 indexed escrowId, address indexed settler);

    // ─── Modifiers ──────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        nextEscrowId = 1;
    }

    // ─── Create ─────────────────────────────────────────────────────
    /**
     * @notice Create a new escrow. Called by the ClearPact backend (operator).
     * @param _payer      Address that will fund the escrow
     * @param _payee      Address that receives funds on settlement
     * @param _token      ERC-20 token address (USDC)
     * @param _amount     Amount in token's smallest unit (6 decimals for USDC)
     * @param _conditionRef  Keccak256 hash of the off-chain conditions JSON
     * @param _authorizedSettler  Address allowed to settle (Phase 2 adapter)
     * @return escrowId   The on-chain escrow ID
     */
    function createEscrow(
        address _payer,
        address _payee,
        address _token,
        uint256 _amount,
        bytes32 _conditionRef,
        address _authorizedSettler
    ) external returns (uint256) {
        require(_payer   != address(0), "Invalid payer");
        require(_payee   != address(0), "Invalid payee");
        require(_token   != address(0), "Invalid token");
        require(_amount  > 0,           "Amount must be > 0");
        require(_payer   != _payee,     "Payer cannot be payee");

        uint256 escrowId = nextEscrowId++;

        escrows[escrowId] = Escrow({
            payer:              _payer,
            payee:              _payee,
            token:              _token,
            amount:             _amount,
            status:             Status.PendingFunding,
            conditionRef:       _conditionRef,
            authorizedSettler:  _authorizedSettler,
            createdAt:          block.timestamp,
            fundedAt:           0,
            settledAt:          0
        });

        emit EscrowCreated(escrowId, _payer, _payee, _token, _amount, _conditionRef);
        return escrowId;
    }

    // ─── Fund ───────────────────────────────────────────────────────
    /**
     * @notice Fund the escrow. Payer must approve this contract first.
     * @dev Transfers _amount of token from msg.sender into this contract.
     */
    function fundEscrow(uint256 _escrowId) external {
        Escrow storage e = escrows[_escrowId];
        require(e.payer  != address(0),           "Escrow does not exist");
        require(e.status == Status.PendingFunding, "Not pending funding");

        // Transfer tokens from funder to this contract
        bool ok = IERC20(e.token).transferFrom(msg.sender, address(this), e.amount);
        require(ok, "Token transfer failed");

        e.status  = Status.Funded;
        e.fundedAt = block.timestamp;

        emit EscrowFunded(_escrowId, msg.sender, e.amount);
    }

    // ─── Settle ─────────────────────────────────────────────────────
    /**
     * @notice Release escrowed funds to payee.
     *         Callable by authorizedSettler (Phase 2 adapter) or contract owner.
     * @dev Replay-protected: status must be Funded or AwaitingVerification.
     */
    function settleEscrow(uint256 _escrowId) external {
        Escrow storage e = escrows[_escrowId];
        require(e.payer != address(0), "Escrow does not exist");
        require(
            e.status == Status.Funded || e.status == Status.AwaitingVerification,
            "Not in settleable state"
        );
        require(
            msg.sender == e.authorizedSettler || msg.sender == owner,
            "Not authorized to settle"
        );

        e.status    = Status.Settled;
        e.settledAt = block.timestamp;

        bool ok = IERC20(e.token).transfer(e.payee, e.amount);
        require(ok, "Token transfer failed");

        emit EscrowSettled(_escrowId, e.payee, e.amount);
    }

    // ─── Refund ─────────────────────────────────────────────────────
    /**
     * @notice Refund escrowed funds back to payer.
     *         Callable by contract owner or payer.
     */
    function refundEscrow(uint256 _escrowId) external {
        Escrow storage e = escrows[_escrowId];
        require(e.payer != address(0), "Escrow does not exist");
        require(
            e.status == Status.Funded || e.status == Status.AwaitingVerification,
            "Not in refundable state"
        );
        require(
            msg.sender == owner || msg.sender == e.payer,
            "Not authorized to refund"
        );

        e.status = Status.Refunded;

        bool ok = IERC20(e.token).transfer(e.payer, e.amount);
        require(ok, "Token transfer failed");

        emit EscrowRefunded(_escrowId, e.payer, e.amount);
    }

    // ─── Cancel ─────────────────────────────────────────────────────
    /**
     * @notice Cancel an unfunded escrow. No funds to move.
     */
    function cancelEscrow(uint256 _escrowId) external {
        Escrow storage e = escrows[_escrowId];
        require(e.payer  != address(0),             "Escrow does not exist");
        require(e.status == Status.PendingFunding,  "Can only cancel unfunded");
        require(
            msg.sender == owner || msg.sender == e.payer,
            "Not authorized to cancel"
        );

        e.status = Status.Cancelled;

        emit EscrowCancelled(_escrowId);
    }

    // ─── Admin ──────────────────────────────────────────────────────
    /**
     * @notice Update the authorized settler for an escrow.
     *         Used to assign the Phase 2 ERC-8004 adapter.
     */
    function setAuthorizedSettler(uint256 _escrowId, address _settler) external onlyOwner {
        Escrow storage e = escrows[_escrowId];
        require(e.payer != address(0), "Escrow does not exist");
        e.authorizedSettler = _settler;
        emit AuthorizedSettlerUpdated(_escrowId, _settler);
    }

    // ─── View ───────────────────────────────────────────────────────
    /**
     * @notice Read full escrow state.
     */
    function getEscrow(uint256 _escrowId) external view returns (
        address payer,
        address payee,
        address token,
        uint256 amount,
        Status  status,
        bytes32 conditionRef,
        address authorizedSettler,
        uint256 createdAt,
        uint256 fundedAt,
        uint256 settledAt
    ) {
        Escrow storage e = escrows[_escrowId];
        require(e.payer != address(0), "Escrow does not exist");
        return (
            e.payer, e.payee, e.token, e.amount,
            e.status, e.conditionRef, e.authorizedSettler,
            e.createdAt, e.fundedAt, e.settledAt
        );
    }
}
