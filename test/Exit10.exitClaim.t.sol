// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';
import './Exit10.t.sol';

contract Exit10_exixtClaimTest is Exit10Test {
  function test_exitClaim() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    assertGt(_balance(exit), 0, 'Check exit balance');

    _eth10k();
    exit10.exit10();
    uint256 initialBalanceUSDC = _balance0();
    uint256 precision = 1e18;
    uint256 exitTokenShare = (_balance(exit) * precision) / ERC20(exit).totalSupply();
    exit10.exitClaim();

    assertEq(_balance(exit), 0, 'Check exit burn');
    assertEq(
      _balance0() - initialBalanceUSDC,
      (exit10.exitTokenRewardsFinal() * exitTokenShare) / precision,
      'Check USD balance'
    );
  }

  function test_exitClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.exitClaim();
  }
}
