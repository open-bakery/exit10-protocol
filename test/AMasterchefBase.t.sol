// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { BaseToken } from '../src/BaseToken.sol';
import { AMasterchefBase, Masterchef } from '../src/Masterchef.sol';
import { ABaseTest } from './ABase.t.sol';

abstract contract AMasterchefBaseTest is ABaseTest {
  address token1;
  address token2;
  BaseToken rewardToken;
  Masterchef masterchef;

  address distributor = address(0xdd);

  uint256 tokenSupply = 10_000 ether;
  uint256 rewardTokenSupply = 10_000 ether;
  uint256 rewardDuration = 100;
  uint256 rewardAmount = 100 ether;
  uint32 allocPoint = 10; // default alloc point used for test pools
  uint256 jump;

  function setUp() public virtual {
    token1 = address(new BaseToken('Stake Token 0', 'STK0'));
    token2 = address(new BaseToken('Stake Token 1', 'STK1'));
    rewardToken = new BaseToken('Reward Token', 'RWT');
    masterchef = new Masterchef(address(rewardToken), rewardDuration);
    masterchef.transferOwnership(distributor);
    _mintAndApprove(token1, tokenSupply, address(masterchef));
    _mintAndApprove(token2, tokenSupply, address(masterchef));
    _mintAndApprove(rewardToken, rewardTokenSupply, address(masterchef));
    // distributor is someone else
    rewardToken.transfer(distributor, rewardTokenSupply);
    vm.prank(distributor);
    _maxApprove(address(rewardToken), address(masterchef));
  }

  // with implicit reward debt check
  function _checkUserInfo(uint256 _pid, address _user, uint256 _amount) internal {
    (, , , , uint256 accRewardPerShare, ) = masterchef.poolInfo(_pid);
    (uint256 stakedAmount, uint256 rewardDebt) = masterchef.userInfo(_pid, _user);
    assertEq(_amount, stakedAmount, 'Check user amount');
    assertEq((accRewardPerShare * stakedAmount) / masterchef.PRECISION(), rewardDebt, 'Check user rewardDebt');
  }

  // this one checks rewardDebt explicitly
  function _checkUserInfo(uint256 _pid, address _user, uint256 _amount, uint256 _rewardDebt) internal {
    (uint256 stakedAmount, uint256 rewardDebt) = masterchef.userInfo(_pid, _user);
    assertEq(_amount, stakedAmount, 'Check user amount');
    assertEq(_rewardDebt / masterchef.PRECISION(), rewardDebt, 'Check user rewardDebt');
  }

  function _checkPoolInfo(uint256 _pid, AMasterchefBase.PoolInfo memory _params) internal {
    (
      address token_,
      uint32 allocPoint_,
      uint64 lastUpdateTime_,
      uint256 totalStaked_,
      uint256 accRewardPerShare_,
      uint256 accUndistributedReward_
    ) = masterchef.poolInfo(_pid);

    assertEq(token_, _params.token, 'Check pool info token');
    assertEq(allocPoint_, _params.allocPoint, 'Check pool info allocPoint');
    assertEq(lastUpdateTime_, _params.lastUpdateTime, 'Check pool info lastUpdateTime');
    assertEq(totalStaked_, _params.totalStaked, 'Check pool info totalStaked');
    assertEq(accRewardPerShare_, _params.accRewardPerShare, 'Check pool info accRewardPerShare');
    assertEq(accUndistributedReward_, _params.accUndistributedReward, 'Check pool info accUndistributedReward');
  }

  function _poolStaked(uint256 _pid) internal view returns (uint256 totalStaked) {
    (, , , totalStaked, , ) = masterchef.poolInfo(_pid);
  }

  function _poolStaked() internal view returns (uint256) {
    return _poolStaked(0);
  }

  function _checkPoolInfo(AMasterchefBase.PoolInfo memory _params) internal {
    _checkPoolInfo(0, _params);
  }

  function _rewardByDuration(uint256 _duration) internal view returns (uint256) {
    return (masterchef.rewardRate() * _duration) / masterchef.PRECISION();
  }

  function _checkRewardBalance(address _user, uint256 _amount) internal {
    assertEq(rewardToken.balanceOf(_user), _amount, 'Check reward balance');
  }

  function _checkRewardBalanceByDuration(address _user, uint256 _duration) internal {
    uint256 balance = _rewardByDuration(_duration);
    assertEq(rewardToken.balanceOf(_user), balance, 'Check reward balance');
  }

  function _checkPending(uint256 _pid, uint256 _amount) internal {
    assertEq(masterchef.pendingReward(_pid, me), _amount, 'Check reward pending amount');
  }

  function _checkPendingByDuration(uint256 _pid, uint256 _duration) internal {
    uint256 reward = _rewardByDuration(_duration);
    assertEq(masterchef.pendingReward(_pid, me), reward, 'Check reward pending amount');
  }

  function _add() internal {
    vm.prank(distributor);
    masterchef.add(allocPoint, token1);
  }

  function _updateRewards() internal {
    vm.prank(distributor);
    masterchef.updateRewards(rewardAmount);
  }

  function _deposit() internal {
    masterchef.deposit(0, 100 ether);
  }

  function _deposit(uint256 amount) internal {
    masterchef.deposit(0, amount);
  }

  function _withdraw() internal {
    masterchef.withdraw(0, 100 ether);
  }

  function _withdraw(uint256 amount) internal {
    masterchef.withdraw(0, amount);
  }

  function _dummyWithdraw() internal {
    masterchef.withdraw(0, 0);
  }

  function _jump(uint256 _time) internal returns (uint256) {
    require(_time < rewardDuration, 'Do not jump too much');
    jump = _time;
    skip(_time);
    return _time;
  }
}
