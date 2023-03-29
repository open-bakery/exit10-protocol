// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10_bootstrapClaimTest is ABaseExit10Test {
  function test_bootstrapClaim() public {
    exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _eth10k();
    (uint256 pending, uint256 reserve, , uint256 bootstrap) = exit10.getBuckets();
    exit10.exit10();

    assertEq(_getLiquidity(), pending + reserve, 'Check liquidity position');

    uint256 usdcBalanceBefore = _balance0();
    uint256 bootBalance = _balance(boot);
    uint256 bootstrapRewardsPlusRefundClaimedBefore = exit10.bootstrapRewardsPlusRefundClaimed();

    exit10.bootstrapClaim();

    uint256 claimableAmount = ((bootBalance / exit10.TOKEN_MULTIPLIER()) * exit10.bootstrapRewardsPlusRefund()) /
      bootstrap;
    assertEq(_balance(boot), 0, 'BOOT tokens burned');
    assertGt(claimableAmount, 0, 'Check claimable > 0');
    assertEq(_balance0(), usdcBalanceBefore + claimableAmount, 'USDC balance increased');
    assertGt(exit10.bootstrapRewardsPlusRefundClaimed(), bootstrapRewardsPlusRefundClaimedBefore, 'Claimed increased');
  }

  function test_bootstrapClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.bootstrapClaim();
  }
}
