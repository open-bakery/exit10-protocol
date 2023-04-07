// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { BaseToken } from '../src/BaseToken.sol';
import { MasterchefExit } from '../src/MasterchefExit.sol';
import { ABaseTest } from './ABase.t.sol';

contract MasterchefExitTest is ABaseTest {
  MasterchefExit public mc;
  uint256 public rewardDuration;
  BaseToken public stakeToken;
  BaseToken public rewardToken;
  uint256 public rewardAmount = 10_000 ether;
  uint256 public stakeAmount = 100 ether;

  function setUp() public {
    rewardToken = new BaseToken('Exit Liquidity', 'EXIT');
    stakeToken = new BaseToken('Stake Token', 'STK');
    rewardDuration = 4 weeks;
    mc = new MasterchefExit(address(rewardToken), rewardDuration);
    stakeToken.mint(address(this), stakeAmount);
    stakeToken.approve(address(mc), type(uint256).max);
    rewardToken.mint(address(mc), rewardAmount);
  }

  function test_updateRewards_RevertIf_NotOwner() public {
    vm.prank(alice);
    vm.expectRevert(bytes('Ownable: caller is not the owner'));
    mc.updateRewards(rewardAmount);
  }

  function test_updateRewards_RevertIf_AmountZero() public {
    _init();
    vm.expectRevert(bytes('MasterchefExit: Can only deposit rewards once'));
    mc.updateRewards(rewardAmount);
  }

  function test_updateRewards_RevertIf_PoolNotSetup() public {
    vm.expectRevert(bytes('MasterchefExit: Must add a pool prior to adding rewards'));
    mc.updateRewards(rewardAmount);
  }

  function test_updateRewards_RevertIf_UpdatingMoreThanOnce() public {
    _init();
    vm.expectRevert(bytes('MasterchefExit: Can only deposit rewards once'));
    mc.updateRewards(rewardAmount);
  }

  function test_updateRewards_RevertIf_NotEnoughRewardTokenBalance() public {
    mc.add(10, address(stakeToken));
    vm.expectRevert(bytes('MasterchefExit: Token balance not sufficient'));
    mc.updateRewards(rewardAmount + 1);
  }

  function test_updateRewards() public {
    _init();
    assertEq(mc.rewardRate(), (rewardAmount * mc.PRECISION()) / rewardDuration, 'Reward rate set');
    assertEq(mc.periodFinish(), block.timestamp + rewardDuration, 'Period finish set');
    assertEq(_balance(rewardToken, address(mc)), rewardAmount, 'Reward token transfered');
  }

  function test_rewards() public {
    _initAndDeposit();
    uint256 interval = 1 days;
    skip(interval);
    uint256 expectedReward = (mc.rewardRate() * interval) / mc.PRECISION();
    mc.withdraw(0, 0);
    _assertWithin(_balance(rewardToken), expectedReward, 10);
  }

  function test_deleteRewards_RevertIf_NotOwner() public {
    _initAndDeposit();
    vm.expectRevert(bytes('Ownable: caller is not the owner'));
    vm.prank(alice);
    mc.stopRewards(rewardAmount);
  }

  function test_deleteRewards() public {
    _initAndDeposit();
    uint256 interval = 1 days;
    skip(interval);
    uint256 expectedReward = (mc.rewardRate() * interval) / mc.PRECISION();
    rewardToken.burn(address(mc), rewardAmount - expectedReward);
    mc.stopRewards(rewardAmount);

    skip(7 days);
    mc.withdraw(0, 0);
    _assertWithin(rewardToken.balanceOf(address(this)), expectedReward, 10);
    _depositAs(alice, stakeAmount);

    skip(7 days);
    _withdrawAs(alice, stakeAmount);
    assertEq(_balance(rewardToken, alice), 0, 'Check alice balance');
    assertEq(rewardToken.totalSupply(), expectedReward, 'Check total supply');
  }

  function testDeleteRewardsTwoDepositors() public {
    _initAndDeposit();
    uint256 interval = 1 days;
    skip(interval);

    uint256 intervalReward = (mc.rewardRate() * interval) / mc.PRECISION();

    _depositAs(alice, stakeAmount);
    skip(interval);

    rewardToken.burn(address(mc), rewardAmount - intervalReward * 2);
    mc.stopRewards(rewardAmount);

    skip(7 days);
    mc.withdraw(0, 0);
    _assertWithin(_balance(rewardToken), intervalReward + intervalReward / 2, 10);
    _withdrawAs(alice, stakeAmount);
    _assertWithin(_balance(rewardToken, alice), intervalReward / 2, 10);
    assertEq(rewardToken.totalSupply(), intervalReward * 2, 'Check total supply');
  }

  function testFirstDepositCollectAllRewards() public {
    _init();
    uint256 interval = 1 days;
    skip(interval);

    uint256 intervalReward = (mc.rewardRate() * interval) / mc.PRECISION();
    _depositAs(alice, stakeAmount);
    assertEq(_balance(rewardToken, alice), intervalReward);
  }

  function testNoStakeInBetweenDeposits() public {
    _init();
    uint256 interval = 1 days;
    skip(interval);
    _depositAs(alice, stakeAmount);
    _withdrawAs(alice, stakeAmount);
    uint256 prevRewardBalance = _balance(rewardToken, alice);
    skip(interval);

    uint256 intervalReward = (mc.rewardRate() * interval) / mc.PRECISION();
    _depositAs(alice, stakeAmount);
    assertEq(_balance(rewardToken, alice), prevRewardBalance + intervalReward);
  }

  function _init() internal {
    mc.add(10, address(stakeToken));
    mc.updateRewards(rewardAmount);
  }

  function _initAndDeposit() internal {
    _init();
    mc.deposit(0, stakeAmount);
  }

  function _depositAs(address _user, uint256 _amount) internal {
    deal(address(stakeToken), _user, _amount);
    vm.startPrank(_user);
    stakeToken.approve(address(mc), type(uint256).max);
    mc.deposit(0, _amount);
    vm.stopPrank();
  }

  function _withdrawAs(address _user, uint256 _amount) internal {
    vm.startPrank(_user);
    mc.withdraw(0, _amount);
    vm.stopPrank();
  }

  function _assertWithin(uint256 _targetValue, uint256 _compareValue, uint256 _basisPoints) internal {
    uint256 range = (_targetValue / 10_000) * _basisPoints;
    bool inRange = (_compareValue <= _targetValue + range && _compareValue >= _targetValue - range);
    assertTrue(inRange, 'Check within range');
  }
}
