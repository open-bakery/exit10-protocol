// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/Masterchef.sol';
import 'forge-std/Test.sol';
import './AMasterchefBase.t.sol';

contract Masterchef_updateRewardsTest is AMasterchefBaseTest {
  function test_updateRewards_RevertIfNoPools() public {
    vm.expectRevert(bytes('Masterchef: Must initiate a pool before updating rewards'));
    _updateRewards();
  }

  function test_updateRewards_RevertIfNotDistriburtor() public {
    vm.expectRevert(bytes('Ownable: caller is not the owner'));
    vm.prank(alice);
    masterchef.updateRewards(100 ether);
  }

  function test_updateRewards_RewardTokenTransfered() public {
    _add();
    _deposit();
    vm.prank(distributor);
    masterchef.updateRewards(rewardAmount);

    assertEq(_balance(rewardToken, address(masterchef)), rewardAmount);
    assertEq(_balance(rewardToken, distributor), rewardTokenSupply - rewardAmount);
  }

  function test_updateRewards_NothingStakedBeforeFirstDeposit() public {
    _add();
    _updateRewards();
    skip(rewardDuration);
    _deposit();
    uint256 jump = _jump(5);

    _checkPendingByDuration(0, jump);
    _dummyWithdraw();
    _checkRewardBalanceByDuration(me, jump);
  }

  function test_updateRewards_AfterStaking() public {
    // not sure this is testing anything special:)
    _add();
    _deposit();
    skip(rewardDuration);
    _updateRewards();
    _jump(1);
    //    _checkPendingByDuration(0, jump); // jiri: no need to test this, we test pending above
    _dummyWithdraw();
    _checkRewardBalanceByDuration(me, jump);
  }

  function test_updateRewards_BeforeStaking() public {
    _add();
    _updateRewards();
    _deposit();
    _jump(10);
    _dummyWithdraw();
    _checkRewardBalanceByDuration(me, jump);
  }

  function test_updateRewards_AfterStakeAndUnstake() public {
    _add();
    _deposit();
    skip(rewardDuration);
    _withdraw();
    skip(rewardDuration);
    _updateRewards();
    skip(rewardDuration);
    _deposit();
    _jump(10);
    uint256 pending = masterchef.rewardRate() * jump;
    _checkPendingByDuration(0, jump);
    _dummyWithdraw();
    _checkRewardBalance(me, pending / masterchef.PRECISION());
    _checkRewardBalance(address(masterchef), rewardAmount - pending / masterchef.PRECISION());
  }
}
