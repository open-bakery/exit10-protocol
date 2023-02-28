// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './BaseToken.sol';
import './interfaces/IExit10.sol';

// Make sure to inherit from Uniswap/merkle-distributor

contract STO is BaseToken {
  using SafeERC20 for ERC20;

  IExit10 public exit10;
  uint256 constant MAX_SUPPLY = 300_000 ether;
  uint256 public acquiredUSDC;

  constructor() BaseToken('Share Token', 'STO') {}

  function setExit10(address instance) external onlyOwner {
    require(address(exit10) == address(0), 'STO: Instance already set');
    exit10 = IExit10(instance);
  }

  function claimSTO() external {}

  function claimExitLiquidity(uint256 amount) external {
    require(exit10.inExitMode(), 'STO: Not in exit mode');

    ERC20 USDC = ERC20(exit10.getAddressUSDC());
    if (acquiredUSDC == 0) acquiredUSDC = USDC.balanceOf(address(this));

    _burn(msg.sender, amount);
    uint256 claim = (amount * acquiredUSDC) / MAX_SUPPLY;
    USDC.safeTransfer(msg.sender, Math.min(claim, USDC.balanceOf(address(this))));
  }
}
