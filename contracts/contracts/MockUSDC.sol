{
  "content": "// SPDX-License-Identifier: MIT\npragma solidity 0.8.20;\n\nimport \"@openzeppelin/contracts/token/ERC20/ERC20.sol\";\n\n/**\n * @notice Minimal 6-decimal USDC mock for local Hardhat testing.\n */\ncontract MockUSDC is ERC20 {\n    constructor() ERC20(\"Mock USDC\", \"USDC\") {\n        _mint(msg.sender, 1_000_000 * 10**6);\n    }\n    function decimals() public pure override returns (uint8) { return 6; }\n    function mint(address to, uint256 amount) external { _mint(to, amount); }\n}\n",
  "path": "/workspace/leviathan-agent/contracts/contracts/MockUSDC.sol"
}
