// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract stakeEthTest is ABaseExit10Test {
  uint256 amount = 10 ether;

  function setUp() public override {
    super.setUp();
    _mintAndApprove(address(exit10), weth, 10 ether, weth);
  }

  function test_stakeEth() public {
    uint256 share = exit10.stakeEth(amount);
    assertGt(share, 0, 'Check staked ETH');
  }

  function test_stakeEth_revertIf_lidoAsZeroAddress() public {
    bytes memory code = address(0).code;
    address targetAddr = exit10.LIDO();
    vm.etch(targetAddr, code);
    assertEq(address(targetAddr).code, bytes(''), 'Check no code in contract');
    vm.expectRevert();
    exit10.stakeEth(amount);
  }
}
