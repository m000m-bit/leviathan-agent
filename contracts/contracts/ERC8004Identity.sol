// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC8004Identity
 * @notice Simplified ERC-8004 "Trustless Agents" identity registry.
 *         Each AI agent receives an ERC-721 NFT carrying its metadata,
 *         capabilities, strategy type, and an append-only reputation log.
 *
 *         Built for The Turing Test Hackathon 2026 — Track 01: AI Trading & Strategy.
 */
contract ERC8004Identity is ERC721URIStorage, Ownable {
    enum RiskProfile { Conservative, Moderate, Aggressive }

    struct Agent {
        address wallet;
        string  name;
        string  description;
        string  capabilities; // comma-separated tags, e.g. "trading,arbitrage"
        string  strategyType; // e.g. "progressive-compounding"
        RiskProfile riskProfile;
        bool    active;
    }

    struct ReputationRecord {
        uint256 score;        // 0-1000 (per-mille)
        string  evidenceURI;  // IPFS / HTTPS link
        uint256 timestamp;
    }

    uint256 private _nextAgentId = 1;

    mapping(uint256 => Agent) public agents;
    mapping(uint256 => ReputationRecord[]) public reputationHistory;
    mapping(address => uint256) public walletToAgentId;

    event AgentRegistered(uint256 indexed agentId, address indexed wallet, string name);
    event AgentUpdated(uint256 indexed agentId);
    event ReputationUpdated(uint256 indexed agentId, uint256 score, string evidenceURI);

    constructor() ERC721("LeviathanAgentIdentity", "LAID") Ownable(msg.sender) {}

    /**
     * @notice Mint a new agent identity NFT for the caller.
     */
    function registerAgent(
        string calldata name,
        string calldata description,
        string calldata capabilities,
        string calldata strategyType,
        RiskProfile     riskProfile,
        string calldata tokenURI_
    ) external returns (uint256 agentId) {
        require(walletToAgentId[msg.sender] == 0, "Already registered");
        agentId = _nextAgentId++;

        agents[agentId] = Agent({
            wallet:       msg.sender,
            name:         name,
            description:  description,
            capabilities: capabilities,
            strategyType: strategyType,
            riskProfile:  riskProfile,
            active:       true
        });

        walletToAgentId[msg.sender] = agentId;

        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, tokenURI_);

        emit AgentRegistered(agentId, msg.sender, name);
    }

    /**
     * @notice Append a reputation record. Caller must be the agent's NFT owner.
     */
    function updateReputation(
        uint256 agentId,
        uint256 score,
        string calldata evidenceURI
    ) external {
        require(_ownerOf(agentId) != address(0), "Agent does not exist");
        require(ownerOf(agentId) == msg.sender || owner() == msg.sender, "Not authorized");
        require(score <= 1000, "Score > 1000");

        reputationHistory[agentId].push(ReputationRecord({
            score:       score,
            evidenceURI: evidenceURI,
            timestamp:   block.timestamp
        }));

        emit ReputationUpdated(agentId, score, evidenceURI);
    }

    function deactivateAgent(uint256 agentId) external onlyOwner {
        require(_ownerOf(agentId) != address(0), "Agent does not exist");
        agents[agentId].active = false;
        emit AgentUpdated(agentId);
    }

    // ── Views ───────────────────────────────────────────────────────

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        require(_ownerOf(agentId) != address(0), "Agent does not exist");
        return agents[agentId];
    }

    function getAgentByWallet(address wallet) external view returns (Agent memory) {
        uint256 id = walletToAgentId[wallet];
        require(id != 0, "No agent for wallet");
        return agents[id];
    }

    function getReputationHistory(uint256 agentId) external view returns (ReputationRecord[] memory) {
        return reputationHistory[agentId];
    }

    function getLatestReputation(uint256 agentId) external view returns (ReputationRecord memory) {
        ReputationRecord[] storage hist = reputationHistory[agentId];
        require(hist.length > 0, "No reputation records");
        return hist[hist.length - 1];
    }

    function totalAgents() external view returns (uint256) {
        return _nextAgentId - 1;
    }
}
