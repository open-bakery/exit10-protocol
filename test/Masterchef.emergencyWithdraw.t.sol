// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/Masterchef.sol';
import 'forge-std/Test.sol';
import './ABase.t.sol';
import './AMasterchefBase.t.sol';

contract Masterchef_emergencyWithdrawTest is AMasterchefBaseTest {
  function test_emergencyWithdraw() public {
    uint256 amount1 = 33 ether;

    uint256 token1BalanceBefore = _balance(token1);

    _add();
    _updateRewards();
    _deposit(amount1);
    _jump(34);

    uint256 poolStaked = _poolStaked();
    uint256 token1BalanceAfterDeposit = _balance(token1);

    masterchef.emergencyWithdraw(0);

    assertEq(token1BalanceAfterDeposit, token1BalanceBefore - amount1);
    assertEq(_balance(token1), token1BalanceBefore); // pool token is returned fully
    assertEq(_balance(rewardToken), 0); // no reward returned
    _checkUserInfo(0, me, 0, 0); // amount/debt reset for user
    assertEq(_poolStaked(), poolStaked - amount1); // pool staked reduced too
  }
}
