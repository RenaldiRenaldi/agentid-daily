// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentID Daily — Check-in & Tips for Agent IDs
/// @notice A free daily check-in + name-based tipping dApp built natively on Agent ID.
///         Every write requires the caller (check-in) or the recipient (tip) to hold an
///         Agent ID (SPACE ID Agent ID, ERC-721, non-transferable).
/// @dev Agent ID contract (BNB Chain): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
///      No funds are ever held by this contract: tips are forwarded immediately.
///      Owner can only pause/unpause check-ins in an emergency; owner can NEVER
///      move, mint, freeze, or withdraw user funds (there are none to move).

interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

contract AgentIDDaily {
    IAgentID public immutable agentID;
    address public immutable owner;
    bool public paused;

    mapping(address => uint256) public lastCheckInDay;
    mapping(address => uint256) public streak;
    mapping(address => uint256) public totalCheckIns;
    mapping(address => uint256) public totalTippedReceived;

    event CheckedIn(address indexed agent, uint256 indexed day, uint256 streak);
    event Tipped(address indexed from, address indexed to, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    error NotAgentIDHolder();
    error AlreadyCheckedInToday();
    error PausedContract();
    error ZeroTip();
    error TipFailed();
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _agentID) {
        agentID = IAgentID(_agentID);
        owner = msg.sender;
    }

    /// @notice Check in once per UTC day. Requires holding an Agent ID.
    /// @dev Streak increments only on consecutive days; a missed day resets it to 1.
    function checkIn() external {
        if (paused) revert PausedContract();
        if (agentID.balanceOf(msg.sender) == 0) revert NotAgentIDHolder();
        uint256 day = block.timestamp / 1 days;
        if (lastCheckInDay[msg.sender] == day) revert AlreadyCheckedInToday();
        if (lastCheckInDay[msg.sender] == day - 1) {
            streak[msg.sender] += 1;
        } else {
            streak[msg.sender] = 1;
        }
        lastCheckInDay[msg.sender] = day;
        totalCheckIns[msg.sender] += 1;
        emit CheckedIn(msg.sender, day, streak[msg.sender]);
    }

    /// @notice Tip an Agent ID holder by their wallet address.
    ///         The frontend resolves a typed `name.ai` to its owner address off-chain,
    ///         so users tip by NAME. The contract verifies the recipient holds an Agent ID.
    /// @dev Forwards the full msg.value immediately; this contract never holds funds.
    function tip(address recipient) external payable {
        if (msg.value == 0) revert ZeroTip();
        if (agentID.balanceOf(recipient) == 0) revert NotAgentIDHolder();
        totalTippedReceived[recipient] += msg.value;
        (bool ok, ) = recipient.call{value: msg.value}("");
        if (!ok) revert TipFailed();
        emit Tipped(msg.sender, recipient, msg.value);
    }

    /// @notice Emergency pause for check-ins only (tips keep working). Owner only.
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Current streak of an address (0 if they never checked in).
    function streakOf(address agent) external view returns (uint256) {
        return streak[agent];
    }
}
