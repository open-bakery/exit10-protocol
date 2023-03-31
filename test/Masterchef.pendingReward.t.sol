// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { AMasterchefBaseTest } from './AMasterchefBase.t.sol';

contract Masterchef_pendingRewardTest is AMasterchefBaseTest {
  function test_pendingReward() public {
    _add();
    _deposit();
    _updateRewards();
    skip(rewardDuration);
    _checkPendingByDuration(0, rewardDuration);
  }

  function test_pendingReward_NoAdditionalAfterRewardDuration() public {
    _add();
    _deposit();
    _updateRewards();
    skip(rewardDuration);
    _checkPendingByDuration(0, rewardDuration);
    _jump(5);
    _checkPendingByDuration(0, rewardDuration);
  }

  function test_pendingReward_AddedLinarly() public {
    _add();
    _deposit();
    _updateRewards();
    _jump(1);
    _checkPendingByDuration(0, 1);
    _jump(2);
    _checkPendingByDuration(0, 3);
    _jump(1);
    _checkPendingByDuration(0, 4);
  }

  function test_pendingRewards_ZeroIfNoUpdateRewards() public {
    _add();
    _deposit();
    skip(rewardDuration);
    _checkPending(0, 0);
  }

  // todo: test with multiple users
  // todo: test with multiple pools
}
