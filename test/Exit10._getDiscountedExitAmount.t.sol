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
    liquidityPerUsd_ = 1e6;
    bootstrapBucket = 100_000 * 1e16;
    exitBucket = 100_000 * 1e16;
  }

  function test_addPercentToAmount() public {
    assertEq(_addPercentToAmount(100, 50000), 600);
    assertEq(_addPercentToAmount(100, 5000), 150);
    assertEq(_addPercentToAmount(100, 500), 105);
    assertEq(_addPercentToAmount(100, 50), 100);
  }

  function test_getPercentFromTarget() public {
    bootstrapBucket = 100_000;
    assertEq(_getPercentFromTarget(100_000 / 2), 5000);
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
