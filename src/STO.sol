// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './BaseToken.sol';
import './interfaces/IExit10.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// Make sure to inherit from Uniswap/merkle-distributor

contract STO is BaseToken {
  IExit10 public exit10;
  address public immutable USDC;

  constructor(address usdc_) BaseToken('Share Token', 'STO') {
    USDC = usdc_;
  }

  function setExit10(address instance) external onlyOwner {
    require(address(exit10) == address(0), 'STO: Instance already set');
    exit10 = IExit10(instance);
  }

  function claimSTO() external {}

  function claimExitLiquidity() external {}
}
