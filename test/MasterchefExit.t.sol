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

  function test_depositWithPermit() public {
    _init();
    uint256 amount = 10 ether;
    deal(address(stakeToken), bob, amount);

    vm.startPrank(bob);
    vm.expectRevert();
    mc.deposit(0, amount);

    mc.depositWithPermit(
      0,
      amount,
      _getPermitParams(bobPK, address(stakeToken), bob, address(mc), amount, block.timestamp)
    );
    vm.stopPrank();

    assertEq(_balance(address(stakeToken), address(mc)), amount);
  }

  function test_updateRewards_RevertIf_NotOwner() public {
    vm.prank(alice);
    vm.expectRevert(bytes('Ownable: caller is not the owner'));
    mc.updateRewards(rewardAmount);
  }

  function test_updateRewards_RevertIf_PoolNotSetup() public {
    vm.expectRevert(bytes('Masterchef: Must initiate a pool before updating rewards'));
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

  function testFirstDepositDoesNotCollectAllRewards() public {
    _init();
    uint256 interval = 1 days;
    skip(interval);
    _depositAs(alice, stakeAmount);
    assertEq(_balance(rewardToken, alice), 0);
  }

  function testNoStakeInBetweenDeposits() public {
    _init();
    uint256 interval = 1 days;
    skip(interval);
    _depositAs(alice, stakeAmount);
    _withdrawAs(alice, stakeAmount);
    uint256 prevRewardBalance = _balance(rewardToken, alice);
    skip(interval);
    _depositAs(alice, stakeAmount);
    assertEq(_balance(rewardToken, alice), prevRewardBalance);
  }

  function testClaimingRewardsAfterPeriodFinished() public {
    _init();
    _depositAs(alice, stakeAmount);
    skip(1 days);
    _withdrawAs(alice, stakeAmount);
    uint256 rewardRate = mc.rewardRate();
    uint256 rewardAmountClaimed = (rewardRate * 1 days) / mc.PRECISION();

    skip(rewardDuration);
    _depositAs(alice, stakeAmount);
    assertApproxEqAbs(_balance(rewardToken, alice), rewardAmountClaimed, 1, 'Check balance == rewardAmount');
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
