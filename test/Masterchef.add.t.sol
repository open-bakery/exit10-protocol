// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { AMasterchefBaseTest, AMasterchefBase } from './AMasterchefBase.t.sol';

contract Masterchef_addTest is AMasterchefBaseTest {
  function test_add_RevertIf_AddingSameTokenTwice() public {
    vm.startPrank(masterchef.owner());
    masterchef.add(10, token1);
    vm.expectRevert(bytes('Masterchef: Token already added'));
    masterchef.add(5, token1);
    vm.stopPrank();
  }

  function test_add_RevertIf_UsingRewardToken() public {
    vm.startPrank(masterchef.owner());
    vm.expectRevert(bytes('Masterchef: Staking reward token not supported'));
    masterchef.add(5, address(rewardToken));
    vm.stopPrank();
  }

  function test_add_RevertIf_AllocPointZero() public {
    vm.startPrank(masterchef.owner());
    vm.expectRevert(bytes('Masterchef: Allocation must be non zero'));
    masterchef.add(0, token1);
    vm.stopPrank();
  }

  function test_add() public {
    vm.startPrank(masterchef.owner());
    masterchef.add(10, token1);
    masterchef.add(30, token2);
    vm.stopPrank();

    _checkPoolInfo(
      0,
      AMasterchefBase.PoolInfo({
        token: token1,
        allocPoint: 10,
        lastUpdateTime: block.timestamp,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
    _checkPoolInfo(
      1,
      AMasterchefBase.PoolInfo({
        token: token2,
        allocPoint: 30,
        lastUpdateTime: block.timestamp,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );
    assertEq(masterchef.totalAllocPoint(), 40);
    assertEq(masterchef.poolLength(), 2);
    assertEq(masterchef.totalClaimedRewards(), 0);
    assertEq(masterchef.rewardRate(), 0);
  }
}
