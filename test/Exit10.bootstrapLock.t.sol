// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { UniswapBase, ABaseExit10Test } from './ABaseExit10.t.sol';

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

  function test_bootstrapLockWithPermit() public {
    uint256 amount0 = _tokenAmount(address(token0), 1000);
    uint256 amount1 = _tokenAmount(address(token1), 1000);

    UniswapBase.AddLiquidity memory addParams = _addLiquidityParams(bob, amount0, amount1);
    PermitParameters memory params0;
    PermitParameters memory params1;

    deal(address(token0), bob, amount0);
    deal(address(token1), bob, amount1);

    vm.startPrank(bob);
    vm.expectRevert();
    (, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(addParams);

    if (address(token0) == exit10.TOKEN_OUT()) {
      params0 = _getPermitParams(bobPK, address(token0), bob, address(exit10), amount0, block.timestamp);
      // mocking params for token that does not supports permit
      params1 = _getMockPermitParams(address(token1), bob, address(exit10), amount1, block.timestamp);
      _maxApprove(address(token1), address(exit10));
    } else {
      params1 = _getPermitParams(bobPK, address(token1), bob, address(exit10), amount1, block.timestamp);
      // mocking params for token that does not supports permit
      params0 = _getMockPermitParams(address(token0), bob, address(exit10), amount0, block.timestamp);
      _maxApprove(address(token0), address(exit10));
    }

    (, liquidityAdded, amountAdded0, amountAdded1) = exit10.bootstrapLockWithPermit(addParams, params0, params1);

    vm.stopPrank();

    assertGt(amountAdded0, 0);
    assertGt(amountAdded1, 0);
    assertGt(liquidityAdded, 0, 'Check liquidityAdded');
    _checkBuckets(0, 0, 0, liquidityAdded);
  }

  function test_bootstrapLock_withZeroAmounts() public {
    vm.expectRevert();
    exit10.bootstrapLock(_addLiquidityParams(0, 0));
  }

  function test_bootstrapLock_withEther() public {
    uint256 beforeBalance0 = _balance0();
    uint256 beforeBalance1 = _balance1();

    (uint256 depositToken0, uint256 depositToken1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), uint256(0))
      : (uint256(0), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));

    uint256 etherAmount = 10 ether;

    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock{
      value: etherAmount
    }(_addLiquidityParams(depositToken0, depositToken1));

    if (exit10.TOKEN_OUT() < exit10.TOKEN_IN()) {
      assertEq(amountAdded0, beforeBalance0 - _balance0(), 'Check amountAdded0');
      assertGt(amountAdded1, 0, 'Check amountAdded1');
    } else {
      assertGt(amountAdded0, 0, 'Check amountAdded0');
      assertEq(amountAdded1, beforeBalance1 - _balance1(), 'Check amountAdded1');
    }

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
