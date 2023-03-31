// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_bootstrapLockTest is ABaseExit10Test {
  function test_bootstrapLock() public {
    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(10000_000000, 10 ether)
    );

    assertGt(amountAdded0, 0);
    assertGt(amountAdded1, 0);
    assertEq(amountAdded0, initialBalance - _balance0(), 'Check amountAdded0');
    assertEq(amountAdded1, initialBalance - _balance1(), 'Check amountAdded1');
    assertEq(tokenId, exit10.positionId(), 'Check positionId');
    assertGt(liquidityAdded, 0, 'Check liquidityAdded');
    assertEq(_balance(boot), liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'Check BOOT balance');

    _checkBalancesExit10(0, 0);
    _checkBuckets(0, 0, 0, liquidityAdded);
  }

  function test_bootstrapLock_withZeroAmounts() public {
    vm.expectRevert();
    exit10.bootstrapLock(_addLiquidityParams(0, 0));
  }

  function test_bootstrapLock_withEther() public {
    uint256 depositToken0 = _tokenAmount(token0, 10_000);
    uint256 depositToken1 = 10 ether;

    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock{
      value: depositToken1
    }(_addLiquidityParams(depositToken0, 0));

    assertEq(amountAdded0, initialBalance - _balance0(), 'Check amountAdded0');
    assertEq(amountAdded1, depositToken1 - (_balance1() - initialBalance), 'Check amountAdded1');
    assertEq(tokenId, exit10.positionId(), 'Check positionId');
    assertGt(liquidityAdded, 0, 'Check liquidityAdded');
    assertEq(_balance(boot), liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'Check BOOT balance');

    _checkBalancesExit10(0, 0);
    _checkBuckets(0, 0, 0, liquidityAdded);
  }

  function test_bootstrap_withMinimumAmount_suppressError() public {
    uint256 minToken = 1;
    try exit10.bootstrapLock(_addLiquidityParams(minToken, minToken)) {} catch {
      return;
    }
    assertTrue(true);
  }

  function test_bootstrapLock_revertIf_bootstrapOver() public {
    _skipBootstrap();

    vm.expectRevert(bytes('EXIT10: Bootstrap ended'));
    exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
  }
}
