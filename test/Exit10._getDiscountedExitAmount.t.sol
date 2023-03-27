// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test, console } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10__getDiscountedExitAmountTest is Test, ABaseExit10Test {
  uint256 liquidityPerUsd_;
  uint256 bootstrapBucket;
  uint256 exitBucket;

  function setUp() public override {
    super.setUp();
  }

  function test_addPercentToAmount() public {
    uint256 amount = 100;
    uint256 percent = 2000;
    assertEq(_addPercentToAmount(amount, percent), 120);
  }

  function _getExitAmount(uint256 _liquidity) internal view virtual override returns (uint256) {
    uint256 percentFromTaget = _getPercentFromTarget(_liquidity) <= 5000 ? 5000 : _getPercentFromTarget(_liquidity);
    uint256 projectedLiquidityPerExit = (liquidityPerUsd_ * percentFromTaget) / PERCENT_BASE;
    uint256 actualLiquidityPerExit = _getActualLiquidityPerExit(exitBucket);
    uint256 liquidityPerExit = actualLiquidityPerExit > projectedLiquidityPerExit
      ? actualLiquidityPerExit
      : projectedLiquidityPerExit;
    return ((_liquidity * DECIMAL_PRECISION) / liquidityPerExit);
  }

  function _getActualLiquidityPerExit(uint256 _exitBucket) internal view virtual override returns (uint256) {
    uint256 exitTokenShareOfBucket = (_exitBucket * 7000) / PERCENT_BASE;
    return (exitTokenShareOfBucket * DECIMAL_PRECISION) / exit10.MAX_EXIT_SUPPLY();
  }

  function _getPercentFromTarget(uint256 _liquidity) internal view virtual override returns (uint256) {
    return (_liquidity * PERCENT_BASE) / bootstrapBucket;
  }
}
