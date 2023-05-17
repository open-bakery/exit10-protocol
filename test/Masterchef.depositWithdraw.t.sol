// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { AMasterchefBaseTest } from './AMasterchefBase.t.sol';

contract Masterchef_depositTest is AMasterchefBaseTest {
  function test_depositWithdraw_TokenTransfered() public {
    uint256 amount1 = 33 ether;
    uint256 amount2 = 22 ether;

    _add();
    _updateRewards();
    _deposit(amount1);

    assertEq(_balance(token1), tokenSupply - amount1);
    assertEq(_balance(token1, address(masterchef)), amount1);

    _withdraw(amount2);
    assertEq(_balance(token1), tokenSupply - amount1 + amount2);
    assertEq(_balance(token1, address(masterchef)), amount1 - amount2);
  }

  function test_depositWithPermit() public {
    uint256 amount1 = 10 ether;
    deal(token1, bob, amount1);

    _add();
    _updateRewards();

    vm.startPrank(bob);
    vm.expectRevert();
    masterchef.deposit(0, amount1);

    masterchef.depositWithPermit(
      0,
      _getPermitParams(bobPK, token1, bob, address(masterchef), amount1, block.timestamp)
    );
    vm.stopPrank();

    assertEq(_balance(token1, address(masterchef)), amount1);
  }

  function test_depositWithdraw_UserInfo() public {
    uint256 amount1 = 36 ether;
    uint256 amount2 = 23 ether;
    uint256 amount3 = 7 ether;

    ERC20(token1).transfer(alice, 100 ether);
    ERC20(token1).transfer(bob, 100 ether);
    vm.prank(alice);
    _maxApprove(token1, address(masterchef));
    vm.prank(bob);
    _maxApprove(token1, address(masterchef));

    _add();
    _updateRewards();

    vm.prank(alice);
    _deposit(amount1);

    vm.prank(bob);
    _deposit(amount2);

    _checkUserInfo(0, alice, amount1, 0);
    _checkUserInfo(0, bob, amount2, 0);

    _jump(20);

    // on someone elses deposit/withdraw, alice's and bob's debt are not touched
    vm.prank(charlie);
    _dummyWithdraw();
    (, , , , uint256 accRewardPerShare, ) = masterchef.poolInfo(0);
    _checkUserInfo(0, alice, amount1, 0);
    _checkUserInfo(0, bob, amount2, 0);

    // alice witdraws => her reward debt updates
    vm.prank(alice);
    _dummyWithdraw();
    _checkUserInfo(0, alice, amount1, amount1 * accRewardPerShare);

    // same for bob
    vm.prank(bob);
    _withdraw(amount3);
    _checkUserInfo(0, alice, amount1, amount1 * accRewardPerShare);
    _checkUserInfo(0, bob, amount2 - amount3, (amount2 - amount3) * accRewardPerShare);

    // As time passes, accRewardPerShare grows (and rewards debt too), but the invariant stays
    _jump(20);
    vm.prank(charlie);
    _withdraw(1);
    (, , , , uint256 accRewardPerShare2, ) = masterchef.poolInfo(0);
    assertGt(accRewardPerShare2, accRewardPerShare);
    _checkUserInfo(0, alice, amount1, amount1 * accRewardPerShare);
    _checkUserInfo(0, bob, amount2 - amount3, (amount2 - amount3) * accRewardPerShare);
  }

  function test_claimRewards_ZeroDepositCollectsRewards() public {
    _add();
    _deposit();
    _updateRewards();
    _jump(11);
    masterchef.deposit(0, 0); // could be any _updatePool causing action
    _checkRewardBalanceByDuration(me, jump);
  }

  function test_UnstakingAsSingleStakerStopsRewards() public {
    _add();
    _deposit();
    _updateRewards();
    uint256 jump1 = _jump(5);
    uint256 expectedReward1 = _rewardByDuration(jump1);
    _withdraw(); // get jump1 sec worth of rewards, stop receiving
    _deposit(); // start receiving again. reward rate is updated because remaining reward is spred to the whole period
    uint256 jump2 = _jump(8);
    uint256 expectedReward2 = _rewardByDuration(jump2);
    _checkPending(0, expectedReward2);
    _dummyWithdraw();
    _checkRewardBalance(me, expectedReward1 + expectedReward2);
    _checkRewardBalance(address(masterchef), rewardAmount - (expectedReward1 + expectedReward2));
    _checkUserInfo(0, me, 100 ether);
  }

  function test_emergencyWithdraw() public {}
}
