// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test, console } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract ExitTokenMintProjectionTest is Test, ABaseExit10Test {
  uint256 minAmountToken0 = 1;
  uint256 maxAmountToken0 = _tokenAmount(usdc, 100_000_000_000);
  uint256 minAmountToken1 = 100_000;
  uint256 maxAmountToken1 = _tokenAmount(weth, 100_000_000_000);

  uint256 constant BOOTSTRAP_TARGET = 47_619_048 * 1e6;
  uint256 constant PERCENTAGE_FLOOR_TARGET = 5000; // How many tokens per USD will be minted.
  uint256 constant EXIT_SUPPLY = 10_000_000 ether;
  uint256 constant LIQUIDITY_PER_USD = 12875978289; // Liquidity per 1_000000
  uint256 constant EXIT_DISCOUNT = 500; // 5%
  uint256 private constant DECIMAL_PRECISION = 1e18;
  uint256 constant USDC_DECIMALS = 1e6;
  uint256 bootstrapBucket;
  uint256 exitBucket;
  uint256 bootstrapRaiseFinalValueUSD;
  uint256 discount;

  function setUp() public override {
    super.setUp();
    bootstrapBucket = BOOTSTRAP_TARGET / 2;
    exitBucket = _getFinalLiquidityFromAmount(_tokenAmount(usdc, 14_285_714));
  }

  function testExitMintProjection() public {
    uint256 liquidityAdded;
    uint256 amountAdded0;
    uint256 amountAdded1;
    uint256 desired0 = 8_500_000 * USDC_DECIMALS;
    uint256 desired1 = 8000 ether;

    console.log('Current ETH price: ', _returnPriceInUSD());
    console.log('Total target liquidity: ', _getLiquidityForBootsrapTarget());

    (liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(desired0, desired1);

    console.log('Total liquidity added: ', liquidityAdded);
    console.log('Percentage from target: ', _getPercentFromTarget(liquidityAdded));
    console.log('Total deposited: ', _getTotalDepositedUSD(amountAdded0, amountAdded1));
    console.log('Total exited minted: ', _getDiscountedExitAmount(liquidityAdded, EXIT_DISCOUNT));

    _swap(address(token0), address(token1), 500_000_000 * USDC_DECIMALS);

    console.log('Liquidity per USDC: ', _liquidityPerUsd(liquidityAdded, amountAdded0, amountAdded1));

    (liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(desired0, desired1);
    exit10.exit10();

    console.log('Total value claimed from bootstrap: ', exit10.bootstrapClaim());
    console.log('Current ETH price: ', _returnPriceInUSD());
    console.log('Target bootstrap liquidity: ', _getLiquidityForBootsrapTarget());
  }

  function _getDiscountedExitAmount(uint256 _liquidity, uint256 _discountPercentage) internal view returns (uint256) {
    return _applyDiscount(_getExitAmount(_liquidity), _discountPercentage);
  }

  function _getExitAmount(uint256 _liquidity) internal view returns (uint256) {
    uint256 percentFromTaget = _getPercentFromTarget(_liquidity) <= 5000 ? 5000 : _getPercentFromTarget(_liquidity);
    uint256 projectedLiquidityPerExit = (LIQUIDITY_PER_USD * percentFromTaget) / PERCENT_BASE;
    uint256 actualLiquidityPerExit = _getActualLiquidityPerExit(exitBucket);
    uint256 liquidityPerExit = actualLiquidityPerExit > projectedLiquidityPerExit
      ? actualLiquidityPerExit
      : projectedLiquidityPerExit;
    // console.log('Projected price: ', (projectedLiquidityPerExit * 1e6) / LIQUIDITY_PER_USD);
    // console.log('Actual price: ', (actualLiquidityPerExit * 1e6) / LIQUIDITY_PER_USD);
    return ((_liquidity * DECIMAL_PRECISION) / liquidityPerExit);
  }

  function _liquidityPerUsd(uint256 _liquidity, uint256 _amount0, uint256 _amount1) internal view returns (uint256) {
    uint256 wethAmountInUSD = (_amount1 * _returnPriceInUSD()) / DECIMAL_PRECISION;
    uint256 totalAmount = wethAmountInUSD + _amount0;
    return (_liquidity * USDC_DECIMALS) / totalAmount;
  }

  function _getTotalDepositedUSD(uint256 _amount0, uint256 _amount1) internal view returns (uint256) {
    uint256 wethAmountInUSD = (_amount1 * _returnPriceInUSD()) / DECIMAL_PRECISION;
    return wethAmountInUSD + _amount0;
  }

  function _returnPriceInUSD() internal view returns (uint256) {
    uint160 sqrtPriceX96;
    (sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    uint256 a = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * USDC_DECIMALS;
    uint256 b = 1 << 192;
    uint256 uintPrice = a / b;
    return (1 ether * 1e6) / uintPrice;
  }

  function _addLiquidity(
    uint256 _desired0,
    uint256 _desired1
  ) internal returns (uint256 _liquidityAdded, uint256 _amountAdded0, uint256 _amountAdded1) {
    (, _liquidityAdded, _amountAdded0, _amountAdded1) = exit10.bootstrapLock(
      UniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: _desired0,
        amount1Desired: _desired1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _getActualLiquidityPerExit(uint256 _exitBucket) internal pure returns (uint256) {
    uint256 exitTokenShareOfBucket = (_exitBucket * 7000) / PERCENT_BASE;
    return (exitTokenShareOfBucket * DECIMAL_PRECISION) / EXIT_SUPPLY;
  }

  function _getPercentFromTarget(uint256 _amountBootstrapped) internal pure returns (uint256) {
    return (_amountBootstrapped * PERCENT_BASE) / _getLiquidityForBootsrapTarget();
  }

  function _getLiquidityForBootsrapTarget() internal pure returns (uint256) {
    return (BOOTSTRAP_TARGET * LIQUIDITY_PER_USD) / USDC_DECIMALS;
  }

  function _getFinalLiquidityFromAmount(uint256 _amount) internal pure returns (uint256) {
    return (_amount * LIQUIDITY_PER_USD) / USDC_DECIMALS;
  }
}
