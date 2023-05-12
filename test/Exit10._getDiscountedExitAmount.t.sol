// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10__getDiscountedExitAmountTest is ABaseExit10Test {
  uint256 liquidityPerUsd_;
  uint256 bootstrapTarget_;
  uint256 exitBucket;

  function setUp() public override {
    super.setUp();
    liquidityPerUsd_ = 2 * 1e6;
  }

  function test_addPercentToAmount() public {
    assertEq(_addPercentToAmount(100, 50000), 600);
    assertEq(_addPercentToAmount(100, 5000), 150);
    assertEq(_addPercentToAmount(100, 500), 105);
    assertEq(_addPercentToAmount(100, 50), 100);
  }

  function test_getValuePerExit() public {
    bootstrapTarget_ = 100_000;
    assertEq(_getPercentFromTarget(100_000 / 2), 5000);
  }

  function test_getExitAmount_liquidityAboveTarget() public {
    bootstrapTarget_ = 100_000 * 1e6;
    exitBucket = 0;
    uint256 liquidity = 120_000 * 1e6;
    // 2 USD per liquidity
    // 1.2 USD per Exit
    // Liquidity = 120_000 / 2 = 60_000
    // Exit = 60_000 / 1.2 = 50_000
    assertEq(_getExitAmount(liquidity), 50_000 * 1e18);
  }

  function test_getExitAmount_liquidityBelowTarget() public {
    bootstrapTarget_ = 100_000 * 1e6;
    exitBucket = 0;
    uint256 liquidity = 20_000 * 1e6;
    // 2 USD per liquidity
    // Minimum price 50 cents per Exit
    // Liquidity = 20_000 / 2 = 10_000;
    // Exit = 10_000 / 0.5 = 20_000
    assertEq(_getExitAmount(liquidity), 20_000 * 1e18);
  }

  function test_getExitAmount_liquidityExitBucketAboveTarget() public {
    bootstrapTarget_ = 100_000 * 1e6;
    exitBucket = 20_000_000 * 1e6;
    uint256 liquidity = 50_000 * 1e6;
    // 2 USD per liquidity
    // Price = 20M * 70% / 10,000,000 = 1.4 per Exit
    // Liquidity = 50_000 / 2  = 25_000;
    // Exit = 50_000 / 1.4 = 35_714_285714285714285714
    assertEq(_getExitAmount(liquidity), 35_714_285714285714285714);
  }

  function _getExitAmount(uint256 _liquidity) internal view virtual override returns (uint256) {
    uint256 bootstrapValueRelativeToTarget = _getPercentFromTarget(_liquidity) <= 5000
      ? 5000
      : _getPercentFromTarget(_liquidity);
    uint256 projectedPricePerExit = (liquidityPerUsd_ * bootstrapValueRelativeToTarget) / RESOLUTION;
    uint256 actualPricePerExit = _getpricePerExitWithMaxSupply(exitBucket);
    uint256 pricePerExit = actualPricePerExit > projectedPricePerExit ? actualPricePerExit : projectedPricePerExit;
    return ((_liquidity * DECIMAL_PRECISION) / pricePerExit);
  }

  function _getpricePerExitWithMaxSupply(uint256 _exitBucket) internal view virtual override returns (uint256) {
    uint256 exitTokenShareOfBucket = (_exitBucket * 7000) / RESOLUTION;
    return (exitTokenShareOfBucket * DECIMAL_PRECISION) / exit10.MAX_EXIT_SUPPLY();
  }

  function _getPercentFromTarget(uint256 _liquidity) internal view virtual override returns (uint256) {
    return (_liquidity * RESOLUTION) / bootstrapTarget_;
  }
}
