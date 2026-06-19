// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC8004Identity.sol";

/**
 * @title StrategyLogger
 * @notice Append-only on-chain log of every trade decision made by the
 *         Leviathan AI agent. Provides the verifiable "Turing Test" benchmark:
 *         every entry, exit, leverage, and PnL is recorded permanently on Mantle.
 *
 *         Trades are grouped into Sessions; sessions are owned by an
 *         ERC-8004-registered agent.
 */
contract StrategyLogger {
    ERC8004Identity public immutable identity;

    enum Direction { Long, Short }

    struct Trade {
        uint256 agentId;
        string  symbol;     // e.g. "SOLUSDT"
        Direction direction;
        uint16  leverage;   // 1 - 1000
        uint256 entryPrice; // 18-decimal
        uint256 exitPrice;  // 18-decimal
        int256  pnl;        // 6-decimal signed (USDC units)
        uint256 timestamp;
    }

    struct Session {
        uint256 agentId;
        uint256 startedAt;
        uint256 endedAt;
        bool    active;
    }

    struct AgentStats {
        uint256 totalTrades;
        uint256 totalWins;
        uint256 totalLosses;
        int256  totalPnL;
    }

    uint256 public nextSessionId = 1;

    mapping(uint256 => Session) public sessions;
    mapping(uint256 => Trade[]) public sessionTrades;
    mapping(uint256 => AgentStats) public agentStats;
    mapping(uint256 => uint256[]) public agentSessions;

    event TradeLogged(
        uint256 indexed sessionId,
        uint256 indexed agentId,
        string  symbol,
        Direction direction,
        uint16  leverage,
        uint256 entryPrice,
        uint256 exitPrice,
        int256  pnl
    );
    event SessionStarted(uint256 indexed sessionId, uint256 indexed agentId);
    event SessionEnded(uint256 indexed sessionId, uint256 indexed agentId, int256 sessionPnL);

    modifier onlyRegisteredAgent(uint256 agentId) {
        ERC8004Identity.Agent memory a = identity.getAgent(agentId);
        require(a.wallet == msg.sender, "Not agent wallet");
        require(a.active, "Agent inactive");
        _;
    }

    constructor(address identity_) {
        require(identity_ != address(0), "Zero identity");
        identity = ERC8004Identity(identity_);
    }

    // ── Session lifecycle ───────────────────────────────────────────

    function startSession(uint256 agentId)
        external
        onlyRegisteredAgent(agentId)
        returns (uint256 sessionId)
    {
        sessionId = nextSessionId++;
        sessions[sessionId] = Session({
            agentId:   agentId,
            startedAt: block.timestamp,
            endedAt:   0,
            active:    true
        });
        agentSessions[agentId].push(sessionId);
        emit SessionStarted(sessionId, agentId);
    }

    function endSession(uint256 sessionId)
        external
        onlyRegisteredAgent(sessions[sessionId].agentId)
    {
        Session storage s = sessions[sessionId];
        require(s.active, "Session not active");
        s.active  = false;
        s.endedAt = block.timestamp;

        int256 sessionPnL = 0;
        Trade[] storage trades = sessionTrades[sessionId];
        for (uint256 i = 0; i < trades.length; i++) sessionPnL += trades[i].pnl;
        emit SessionEnded(sessionId, s.agentId, sessionPnL);
    }

    // ── Trade logging ───────────────────────────────────────────────

    function logTrade(
        uint256   sessionId,
        string calldata symbol,
        Direction direction,
        uint16    leverage,
        uint256   entryPrice,
        uint256   exitPrice,
        int256    pnl,
        uint256   timestamp
    ) external onlyRegisteredAgent(sessions[sessionId].agentId) {
        Session storage s = sessions[sessionId];
        require(s.active, "Session not active");
        require(leverage >= 1 && leverage <= 1000, "Invalid leverage");

        sessionTrades[sessionId].push(Trade({
            agentId:    s.agentId,
            symbol:     symbol,
            direction:  direction,
            leverage:   leverage,
            entryPrice: entryPrice,
            exitPrice:  exitPrice,
            pnl:        pnl,
            timestamp:  timestamp
        }));

        AgentStats storage stats = agentStats[s.agentId];
        stats.totalTrades += 1;
        stats.totalPnL    += pnl;
        if (pnl >= 0) stats.totalWins   += 1;
        else          stats.totalLosses += 1;

        emit TradeLogged(sessionId, s.agentId, symbol, direction, leverage, entryPrice, exitPrice, pnl);
    }

    // ── Views ───────────────────────────────────────────────────────

    function getSessionTrades(uint256 sessionId) external view returns (Trade[] memory) {
        return sessionTrades[sessionId];
    }

    function getAgentStats(uint256 agentId)
        external
        view
        returns (uint256 totalTrades, uint256 winRateBps, int256 totalPnL)
    {
        AgentStats storage s = agentStats[agentId];
        totalTrades = s.totalTrades;
        totalPnL    = s.totalPnL;
        winRateBps  = s.totalTrades > 0 ? (s.totalWins * 10_000) / s.totalTrades : 0;
    }

    function getAgentSessions(uint256 agentId) external view returns (uint256[] memory) {
        return agentSessions[agentId];
    }

    function getSessionPnL(uint256 sessionId) external view returns (int256 pnl) {
        Trade[] storage trades = sessionTrades[sessionId];
        for (uint256 i = 0; i < trades.length; i++) pnl += trades[i].pnl;
    }
}
