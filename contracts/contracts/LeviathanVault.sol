// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LeviathanVault
 * @notice USDC vault for the Leviathan AI Trading Agent.
 *
 *         Implements the human-proven "progressive compounding" risk discipline
 *         on-chain:
 *          - Milestone profit auto-withdrawals: at $35 equity → $10 to safe wallet,
 *            at $60 equity → $20 to safe wallet (the trader's own "出金意識" rule).
 *          - Daily session profit cap of $100 (the trader's own "1日の上限" rule).
 *          - Only the registered AI agent wallet can record trade outcomes.
 *
 *         All USDC amounts use 6-decimal precision (matching real USDC).
 */
contract LeviathanVault is Ownable {
    IERC20 public immutable USDC;

    uint256 public constant MILESTONE_1_EQUITY   = 35e6;  // $35
    uint256 public constant MILESTONE_1_WITHDRAW = 10e6;  // $10
    uint256 public constant MILESTONE_2_EQUITY   = 60e6;  // $60
    uint256 public constant MILESTONE_2_WITHDRAW = 20e6;  // $20
    uint256 public constant SESSION_DAILY_CAP    = 100e6; // $100

    address public agent;
    address public safeWallet;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalProfitWithdrawn;

    uint256 public sessionProfit;
    uint256 public sessionStartTimestamp;
    uint256 public sessionProfitToday;

    bool public milestone1Hit;
    bool public milestone2Hit;

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount, bool isProfit);
    event ProfitLocked(uint256 equity, uint256 amount, address safeWallet);
    event SessionLimitHit(uint256 attempted, uint256 cap);
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event SafeWalletUpdated(address indexed oldWallet, address indexed newWallet);

    modifier onlyAgent() {
        require(msg.sender == agent, "Not the registered agent");
        _;
    }

    constructor(address usdc_, address agent_, address safeWallet_) Ownable(msg.sender) {
        require(usdc_       != address(0), "Zero USDC");
        require(agent_      != address(0), "Zero agent");
        require(safeWallet_ != address(0), "Zero safe wallet");
        USDC       = IERC20(usdc_);
        agent      = agent_;
        safeWallet = safeWallet_;
        sessionStartTimestamp = block.timestamp;
    }

    // ── Capital flows ───────────────────────────────────────────────

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(USDC.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= USDC.balanceOf(address(this)), "Insufficient");
        require(USDC.transfer(msg.sender, amount), "transfer failed");
        totalWithdrawn += amount;
        emit Withdrawn(msg.sender, amount, false);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = USDC.balanceOf(address(this));
        require(balance > 0, "No balance");
        require(USDC.transfer(owner(), balance), "transfer failed");
        totalWithdrawn += balance;
        emit Withdrawn(owner(), balance, false);
    }

    // ── Trade reporting ─────────────────────────────────────────────

    /**
     * @notice Agent reports a realised profit. Enforces daily cap, then
     *         checks if equity crossed a milestone and auto-locks profit.
     */
    function recordProfit(uint256 profitAmount) external onlyAgent {
        require(profitAmount > 0, "Zero profit");
        _resetSessionIfNeeded();

        if (sessionProfitToday + profitAmount > SESSION_DAILY_CAP) {
            uint256 allowed = SESSION_DAILY_CAP - sessionProfitToday;
            emit SessionLimitHit(profitAmount, SESSION_DAILY_CAP);
            require(allowed > 0, "Daily session cap reached");
            profitAmount = allowed;
        }

        sessionProfit      += profitAmount;
        sessionProfitToday += profitAmount;

        _checkMilestones();
    }

    function recordLoss(uint256 lossAmount) external onlyAgent {
        require(lossAmount > 0, "Zero loss");
        _resetSessionIfNeeded();
        sessionProfit = sessionProfit > lossAmount ? sessionProfit - lossAmount : 0;
    }

    function startSession() external onlyAgent {
        sessionStartTimestamp = block.timestamp;
        sessionProfitToday    = 0;
    }

    // ── Internal ────────────────────────────────────────────────────

    function _checkMilestones() internal {
        uint256 equity = getEquity();

        if (!milestone1Hit && equity >= MILESTONE_1_EQUITY) {
            milestone1Hit = true;
            _lockProfit(MILESTONE_1_WITHDRAW);
        }
        if (!milestone2Hit && equity >= MILESTONE_2_EQUITY) {
            milestone2Hit = true;
            _lockProfit(MILESTONE_2_WITHDRAW);
        }
    }

    function _lockProfit(uint256 amount) internal {
        uint256 balance = USDC.balanceOf(address(this));
        uint256 toSend  = amount > balance ? balance : amount;
        if (toSend == 0) return;
        require(USDC.transfer(safeWallet, toSend), "transfer failed");
        totalProfitWithdrawn += toSend;
        emit ProfitLocked(getEquity(), toSend, safeWallet);
        emit Withdrawn(safeWallet, toSend, true);
    }

    function _resetSessionIfNeeded() internal {
        if (block.timestamp >= sessionStartTimestamp + 1 days) {
            sessionStartTimestamp = block.timestamp;
            sessionProfitToday    = 0;
        }
    }

    // ── Admin ───────────────────────────────────────────────────────

    function setAgent(address newAgent) external onlyOwner {
        require(newAgent != address(0), "Zero");
        emit AgentUpdated(agent, newAgent);
        agent = newAgent;
    }

    function setSafeWallet(address newSafe) external onlyOwner {
        require(newSafe != address(0), "Zero");
        emit SafeWalletUpdated(safeWallet, newSafe);
        safeWallet = newSafe;
    }

    // ── Views ───────────────────────────────────────────────────────

    function getEquity() public view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    function getSessionInfo() external view returns (
        uint256 profit,
        uint256 profitToday,
        uint256 sessionStart
    ) {
        return (sessionProfit, sessionProfitToday, sessionStartTimestamp);
    }
}
