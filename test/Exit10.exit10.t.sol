// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';
import './Exit10.t.sol';

contract Exit10_exit10Test is Exit10Test {
  // todo: test what happens if no bootstrap / no bonds

  function test_exit10_RevertIf_NotOutOfRange() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Current Tick not below TICK_LOWER'));
    exit10.exit10();
  }

  function test_exit10() public {
    exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getBuckets();
    _checkBalancesExit10(0, 0);

    _eth10k();
    uint128 totalLiquidity = __liquidity();
    exit10.exit10();

    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertTrue(__liquidity() - pending == reserve, 'Check reserve amount');
    assertTrue(token0.balanceOf(address(exit10)) != 0, 'Check acquired USD != 0');

    uint256 AcquiredUSD = token0.balanceOf(address(exit10)) + token0.balanceOf(address(sto));
    uint256 exitLiquidityPlusBootstrap = totalLiquidity - reserve;

    assertTrue(exit + bootstrap == exitLiquidityPlusBootstrap, 'Check Exitbucket');

    uint256 exitBootstrapUSD = (bootstrap * AcquiredUSD) / exitLiquidityPlusBootstrap;
    uint256 exitLiquidityUSD = (AcquiredUSD - exitBootstrapUSD);
    uint256 share = exitLiquidityUSD / 10;

    assertTrue(exit10.bootstrapRewardsPlusRefund() == exitBootstrapUSD + share, 'Check Bootstrap USD share amount');
    assertTrue(exit10.teamPlusBackersRewards() == share * 2, 'Check team plus backers'); // 20%
    assertTrue(AcquiredUSD - (exitBootstrapUSD + share * 3) == exit10.exitTokenRewardsFinal(), 'Check exit liquidity');
    assertTrue(ERC20(token1).balanceOf(address(exit10)) == 0, 'Check balance token1 == 0');
  }
}
