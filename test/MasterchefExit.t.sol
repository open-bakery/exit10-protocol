// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/MasterchefExit.sol';
import 'forge-std/Test.sol';

contract MasterchefExitTest is Test {
  MasterchefExit public mc;
  uint256 public rewardDuration;
  BaseToken public stakeToken;
  BaseToken public rewardToken;
  uint256 public rewardAmount = 10_000 ether;
  uint256 public stakeAmount = 100 ether;
  address alice = address(0x0a);
  address bob = address(0x0b);
  address charlie = address(0x0c);

  function setUp() public {
    rewardToken = new BaseToken('Exit Liquidity', 'EXIT');
    stakeToken = new BaseToken('Stake Token', 'STK');
    rewardDuration = 4 weeks;
    mc = new MasterchefExit(address(rewardToken), rewardDuration);
    mc.add(10, address(stakeToken));
    rewardToken.mint(address(this), rewardAmount);
    stakeToken.mint(address(this), stakeAmount);
    rewardToken.approve(address(mc), type(uint256).max);
    stakeToken.approve(address(mc), type(uint256).max);
    mc.updateRewards(rewardAmount);
    mc.deposit(0, stakeAmount);
  }

  function testSetup() public {
    assertTrue(rewardToken.balanceOf(address(mc)) == rewardAmount, 'Check balance reward');
    assertTrue(mc.rewardRate() == ((rewardAmount * 1e18) / mc.REWARDS_DURATION()), 'Check reward rate');
  }

  function testRewards() public {
    uint256 interval = 1 days;
    skip(interval);
    uint256 expectedReward = (mc.rewardRate() * interval) / 1e18;
    mc.withdraw(0, 0);
    _assertWithin(rewardToken.balanceOf(address(this)), expectedReward, 10);
  }

  function testDeleteRewards() public {
    uint256 interval = 1 days;
    skip(interval);
    uint256 expectedReward = (mc.rewardRate() * interval) / 1e18;
    rewardToken.burn(address(mc), rewardAmount - expectedReward);
    mc.stopRewards();
    skip(7 days);
    mc.withdraw(0, 0);
    _assertWithin(rewardToken.balanceOf(address(this)), expectedReward, 10);
    _depositAs(alice, stakeAmount);
    skip(7 days);
    _withdrawAs(alice, stakeAmount);
    assertTrue(rewardToken.balanceOf(alice) == 0, 'Check alice balance');
    assertTrue(rewardToken.totalSupply() == expectedReward, 'Check total supply');
  }

  function testDeleteRewardsTwoDepositors() public {
    uint256 interval = 1 days;
    skip(interval);
    uint256 expectedIntervalReward = (mc.rewardRate() * interval) / 1e18;
    _depositAs(alice, stakeAmount);
    skip(interval);
    rewardToken.burn(address(mc), rewardAmount - expectedIntervalReward * 2);
    mc.stopRewards();
    skip(7 days);
    mc.withdraw(0, 0);
    _assertWithin(rewardToken.balanceOf(address(this)), expectedIntervalReward + expectedIntervalReward / 2, 10);
    _withdrawAs(alice, stakeAmount);
    _assertWithin(rewardToken.balanceOf(alice), expectedIntervalReward / 2, 10);
    assertTrue(rewardToken.totalSupply() == expectedIntervalReward * 2, 'Check total supply');
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

  function _assertWithin(
    uint256 _targetValue,
    uint256 _compareValue,
    uint256 _basisPoints
  ) internal {
    uint256 range = (_targetValue / 10_000) * _basisPoints;
    bool inRange = (_compareValue <= _targetValue + range && _compareValue >= _targetValue - range);
    assertTrue(inRange, 'Check within range');
  }
}
