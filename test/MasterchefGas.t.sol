// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/BaseToken.sol';
import '../src/Masterchef.sol';
import 'forge-std/Test.sol';

contract MasterchefGasTest is Test {
  BaseToken st;
  BaseToken rw;
  Masterchef mc;

  function setUp() public {
    uint256 duration = 800;
    st = new BaseToken('Stake Token', 'STK');
    rw = new BaseToken('Reward Token', 'RWT');
    st.mint(address(this), 10_000 ether);
    rw.mint(address(this), 10_000 ether);
    mc = new Masterchef(address(rw), duration);
    st.approve(address(mc), type(uint256).max);
    rw.approve(address(mc), type(uint256).max);
    mc.add(10, address(st));
    mc.deposit(0, 100 ether);
    mc.setRewardDistributor(address(this));
    mc.updateRewards(100 ether);
    skip(duration);
  }

  function testPendingFees() public {
    uint256 pending = mc.pendingReward(0, address(this));
    assertTrue(pending == 100 ether);
  }
}
