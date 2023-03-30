// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/Masterchef.sol';
import 'forge-std/Test.sol';
import './AMasterchefBase.t.sol';

contract MasterchefTest is AMasterchefBaseTest {
  function test_poolInfo_Updates() public {
    // setup, no deposit, arbitrary wait
    _add();
    _updateRewards();
    uint256 ts1 = block.timestamp;
    _jump(66);
    _checkPoolInfo(
      AMasterchefBase.PoolInfo({
        token: token1,
        allocPoint: allocPoint,
        lastUpdateTime: ts1,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );

    // right after deposit
    uint256 deposit = 50 ether;
    _deposit(deposit);
    _checkPoolInfo(
      AMasterchefBase.PoolInfo({
        token: token1,
        allocPoint: allocPoint,
        lastUpdateTime: block.timestamp,
        totalStaked: deposit,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );

    // after deposit and some more time
    _jump(50);
    _dummyWithdraw(); // causes pool recalc
    _checkPoolInfo(
      AMasterchefBase.PoolInfo({
        token: token1,
        allocPoint: allocPoint,
        lastUpdateTime: block.timestamp,
        totalStaked: deposit,
        accRewardPerShare: (_rewardByDuration(jump) * masterchef.PRECISION()) / deposit,
        accUndistributedReward: 0
      })
    );

    _withdraw(deposit);
  }

  function test_poolInfo_MultiplePools() public {
    uint256 allocPoint0 = 60;
    uint256 allocPoint1 = 40;
    uint256 totalAllocPoint = allocPoint0 + allocPoint1;
    vm.startPrank(masterchef.owner());
    masterchef.add(allocPoint0, token1);
    masterchef.add(allocPoint1, token2);
    vm.stopPrank();
    _updateRewards();

    uint256 deposit0 = 80 ether;
    uint256 deposit1 = 70 ether;

    masterchef.deposit(0, deposit0);
    masterchef.deposit(1, deposit1);

    _jump(rewardDuration / 2);
    uint256 baseReward = masterchef.rewardRate() * jump;
    masterchef.withdraw(0, 0);
    masterchef.withdraw(1, 0);

    assertEq(masterchef.totalAllocPoint(), totalAllocPoint);
    _checkPoolInfo(
      0,
      AMasterchefBase.PoolInfo({
        token: address(token1),
        allocPoint: allocPoint0,
        lastUpdateTime: block.timestamp,
        totalStaked: deposit0,
        accRewardPerShare: ((baseReward * allocPoint0)) / totalAllocPoint / deposit0,
        accUndistributedReward: 0
      })
    );
    _checkPoolInfo(
      1,
      AMasterchefBase.PoolInfo({
        token: address(token2),
        allocPoint: allocPoint1,
        lastUpdateTime: block.timestamp,
        totalStaked: deposit1,
        accRewardPerShare: ((baseReward * allocPoint1) / totalAllocPoint) / deposit1,
        accUndistributedReward: 0
      })
    );
  }
}
