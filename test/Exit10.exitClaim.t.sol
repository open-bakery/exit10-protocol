// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test, console } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10_exitClaimTest is ABaseExit10Test {
  function test_exitClaim() public {
    // setup: create bond for myself and alice, skip sime time to accumulate fees
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();

    vm.startPrank(alice);
    (uint256 bondIdAlice, uint256 bondAmountAlice) = _createBond(alice);
    skip(100);
    exit10.convertBond(bondIdAlice, _removeLiquidityParams(bondAmountAlice));
    vm.stopPrank();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    // exit10
    _eth10k();
    exit10.exit10();
    uint256 initialBalanceUSDC = _balance0();
    uint256 precision = 1e18;
    uint256 exitTokenShare = (_balance(exit) * precision) / ERC20(exit).totalSupply();

    // claim as alice first so that we don't start with zero
    vm.prank(alice);
    exit10.exitClaim();

    uint256 exitTokenRewardsClaimedBefore = exit10.exitTokenRewardsClaimed();

    // action!
    exit10.exitClaim();

    assertEq(_balance(exit), 0, 'Check exit burn');
    assertEq(
      _balance0(),
      initialBalanceUSDC + (exit10.exitTokenRewardsFinal() * exitTokenShare) / precision,
      'Check USD balance'
    );

    assertEq(
      exit10.exitTokenRewardsClaimed(),
      exitTokenRewardsClaimedBefore + (exit10.exitTokenRewardsFinal() * exitTokenShare) / precision,
      'Remaining reward decreased'
    );
  }

  function test_exitClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.exitClaim();
  }
}
