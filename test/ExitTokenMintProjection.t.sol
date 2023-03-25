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

  uint256 bootstrapBucket;
  uint256 exitBucket;
  uint256 bootstrapRaiseFinalValueUSD;
  uint256 discount;

  function setUp() public override {
    super.setUp();
    bootstrapBucket = bootstrapTarget / 2;
    exitBucket = _getFinalLiquidityFromAmount(_tokenAmount(usdc, 14_285_714));
  }

  function testExitMintProjection() public {
    uint256 liquidityAdded;
    uint256 amountAdded0;
    uint256 amountAdded1;
    uint256 amount0 = 8_500_000 * USDC_DECIMALS;
    uint256 amount1 = 8000 ether;

    console.log('Current ETH price: ', _returnPriceInUSD());
    console.log('Total target liquidity: ', _getLiquidityForBootsrapTarget());

    (liquidityAdded, amountAdded0, amountAdded1) = _bootstrapLock(amount0, amount1);

    console.log('Total liquidity added: ', liquidityAdded);
    console.log('Percentage from target: ', _getPercentFromTarget(liquidityAdded));
    console.log('Total deposited: ', _getTotalDepositedUSD(amountAdded0, amountAdded1));
    console.log('Total exited minted: ', _getDiscountedExitAmount(liquidityAdded, exitDiscount));

    _swap(address(token0), address(token1), 500_000_000 * USDC_DECIMALS);

    console.log('Liquidity per USDC: ', _liquidityPerUsd(liquidityAdded, amountAdded0, amountAdded1));

    (liquidityAdded, amountAdded0, amountAdded1) = _bootstrapLock(amount0, amount1);
    exit10.exit10();

    console.log('Total value claimed from bootstrap: ', exit10.bootstrapClaim());
    console.log('Current ETH price: ', _returnPriceInUSD());
    console.log('Target bootstrap liquidity: ', _getLiquidityForBootsrapTarget());
  }
}
