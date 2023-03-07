// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/Masterchef.sol';
import 'forge-std/Test.sol';

contract MasterchefTest is Test {
  BaseToken st0;
  BaseToken st1;
  BaseToken rw;
  Masterchef mc;
  uint256 rewardDuration = 100_000;
  address alice = address(0x0a);
  address bob = address(0x0b);
  address charlie = address(0x0c);
  uint256 amount = 10_000 ether;
  uint256 rewardAmount = 100 ether;

  function setUp() public {
    st0 = new BaseToken('Stake Token 0', 'STK0');
    st1 = new BaseToken('Stake Token 1', 'STK1');
    rw = new BaseToken('Reward Token', 'RWT');
    mc = new Masterchef(address(rw), rewardDuration);
    mc.setRewardDistributor(address(this));
    _mintAndApprove(st0, amount, address(mc));
    _mintAndApprove(st1, amount, address(mc));
    _mintAndApprove(rw, rewardAmount, address(mc));
  }

  function testPendingFees() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    mc.updateRewards(rewardAmount);
    skip(rewardDuration);
    _checkPending(0, (mc.rewardRate() * rewardDuration) / mc.PRECISION());
  }

  function testUpdateRewardsRevert() public {
    vm.expectRevert(bytes('Masterchef: Must initiate a pool before updating rewards'));
    mc.updateRewards(100 ether);
  }

  function testPoolSetup() public {
    mc.add(10, address(st0));
    _checkPoolData(
      0,
      AMasterchefBase.PoolInfo({
        token: address(st0),
        allocPoint: 10,
        lastUpdateTime: block.timestamp,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
  }

  function testClaimRewardsWithZeroDeposit() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    mc.updateRewards(rewardAmount);
    skip(rewardDuration);
    _checkPending(0, (mc.rewardRate() * rewardDuration) / mc.PRECISION());
    mc.deposit(0, 0);
    _checkRewardBalance(address(this), (mc.rewardRate() * rewardDuration) / mc.PRECISION());
  }

  function testUpdateRewardsNoStaking() public {
    mc.add(10, address(st0));
    mc.updateRewards(rewardAmount);
    skip(rewardDuration);
    mc.deposit(0, 100 ether);
    uint256 jump = 5 seconds;
    skip(jump);
    uint256 pending = mc.rewardRate() * jump;
    _checkPending(0, pending / mc.PRECISION());
    mc.withdraw(0, 0);
    _checkRewardBalance(address(this), pending / mc.PRECISION());
  }

  function testNoUpdateRewardsAfterStaking() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    skip(rewardDuration);
    _checkPending(0, 0);
  }

  function testUpdateRewardsAfterStaking() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    skip(rewardDuration);
    mc.updateRewards(rewardAmount);
    uint256 jump = 1 seconds;
    skip(jump);
    uint256 pending = mc.rewardRate() * jump;
    _checkPending(0, pending / mc.PRECISION());
    mc.withdraw(0, 0);
    _checkRewardBalance(address(this), pending / mc.PRECISION());
  }

  function testUpdateRewardsBeforeStaking() public {
    mc.add(10, address(st0));
    mc.updateRewards(rewardAmount);
    mc.deposit(0, 100 ether);
    uint256 jump = 10 seconds;
    uint256 pending = mc.rewardRate() * jump;
    skip(jump);
    _checkPending(0, pending / mc.PRECISION());
    mc.withdraw(0, 0);
    _checkRewardBalance(address(this), pending / mc.PRECISION());
  }

  function testStakeUnstakeUpdateRewards() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    skip(rewardDuration);
    mc.withdraw(0, 100 ether);
    skip(rewardDuration);
    mc.updateRewards(rewardAmount);
    skip(rewardDuration);
    mc.deposit(0, 100 ether);
    uint256 jump = 10 seconds;
    skip(jump);
    uint256 pending = mc.rewardRate() * jump;
    _checkPending(0, pending / mc.PRECISION());
    mc.withdraw(0, 0);
    assertTrue(rw.balanceOf(address(this)) != 0, 'Check zero reward balance');
    _checkRewardBalance(address(this), pending / mc.PRECISION());
    _checkRewardBalance(address(mc), rewardAmount - pending / mc.PRECISION());
  }

  function testUpdateRewardsUnstakeCrossPeriodFinsihRestake() public {
    mc.add(10, address(st0));
    mc.deposit(0, 100 ether);
    mc.updateRewards(rewardAmount);
    skip(1 seconds);
    mc.withdraw(0, 100 ether);
    skip(rewardDuration);
    mc.deposit(0, 100 ether);
    uint256 jump = 10 seconds;
    skip(jump);
    uint256 pending = mc.rewardRate() * jump;
    _checkPending(0, pending / mc.PRECISION());
    mc.withdraw(0, 0);
    assertTrue(rw.balanceOf(address(this)) != 0, 'Check zero reward balance');
    _checkRewardBalance(address(this), (pending / mc.PRECISION()) + rewardAmount / rewardDuration);
    _checkRewardBalance(address(mc), rewardAmount - (pending / mc.PRECISION() + rewardAmount / rewardDuration));
    _checkUserInfo(0, address(this), 100 ether);
  }

  function testMultiplePools() public {
    uint256 share0 = 60;
    uint256 share1 = 100 - share0;
    mc.add(share0, address(st0));
    mc.add(share1, address(st1));
    mc.updateRewards(rewardAmount);
    skip(rewardDuration);
    _checkPoolData(
      0,
      AMasterchefBase.PoolInfo({
        token: address(st0),
        allocPoint: share0,
        lastUpdateTime: block.timestamp - rewardDuration,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
    _checkPoolData(
      1,
      AMasterchefBase.PoolInfo({
        token: address(st1),
        allocPoint: share1,
        lastUpdateTime: block.timestamp - rewardDuration,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
    mc.deposit(0, 100 ether);
    uint256 undistributedSt0 = (rewardAmount * share0) / 100;
    skip(rewardDuration / 2);
    uint256 pendingst0 = (undistributedSt0 * share0) / 100 / 2;
    _checkPending(0, pendingst0);
    mc.deposit(1, 100 ether);
    _checkPoolData(
      1,
      AMasterchefBase.PoolInfo({
        token: address(st1),
        allocPoint: share1,
        lastUpdateTime: block.timestamp,
        totalStaked: 100 ether,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
  }

  function _checkUserInfo(
    uint256 _pid,
    address _user,
    uint256 _amount
  ) internal {
    (, , , , uint256 accRewardPerShare, ) = mc.poolInfo(_pid);
    (uint256 stakedAmount, uint256 rewardDebt) = mc.userInfo(_pid, _user);
    assertTrue(_amount == stakedAmount, 'Check user amount');
    assertTrue((accRewardPerShare * stakedAmount) / mc.PRECISION() == rewardDebt, 'Check user rewardDebt');
  }

  function _checkPoolData(uint256 _pid, AMasterchefBase.PoolInfo memory _params) internal {
    (
      address token,
      uint256 allocPoint,
      uint256 lastUpdateTime,
      uint256 totalStaked,
      uint256 accRewardPerShare,
      uint256 accUndistributedReward
    ) = mc.poolInfo(_pid);

    assertTrue(token == _params.token, 'Check pool info token');
    assertTrue(allocPoint == _params.allocPoint, 'Check pool info allocPoint');
    assertTrue(lastUpdateTime == _params.lastUpdateTime, 'Check pool info lastUpdateTime');
    assertTrue(totalStaked == _params.totalStaked, 'Check pool info totalStaked');
    assertTrue(accRewardPerShare == _params.accRewardPerShare, 'Check pool info accRewardPerShare');
    assertTrue(accUndistributedReward == _params.accUndistributedReward, 'Check pool info accUndistributedReward');
  }

  function _checkRewardBalance(address _user, uint256 _amount) internal {
    assertTrue(rw.balanceOf(_user) == _amount, 'Check reward balance');
  }

  function _checkPending(uint256 _pid, uint256 _amount) internal {
    assertTrue(mc.pendingReward(_pid, address(this)) == _amount, 'Check reward pending amount');
  }

  function _mintAndApprove(
    BaseToken _token,
    uint256 _amount,
    address _spender
  ) internal {
    _token.mint(address(this), _amount);
    _token.approve(_spender, type(uint256).max);
  }
}
