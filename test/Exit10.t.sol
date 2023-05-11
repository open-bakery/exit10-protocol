// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10Test is ABaseExit10Test {
  function setUp() public override {
    super.setUp();
  }

  function test_setup() public {
    assertEq(exit10.positionId(), 0, 'Check positionId');
    _checkBalances(initialBalance, initialBalance);
    _checkBalancesExit10(0, 0);

    _checkBuckets(0, 0, 0, 0);
    assertEq(exit10.exitTokenSupplyFinal(), 0, 'setup exitTokenSupplyFinal');
    assertEq(exit10.exitTokenRewardsFinal(), 0, 'setup exitTokenRewardsFinal');
    assertEq(exit10.bootstrapRewardsPlusRefund(), 0, 'setup bootstrapRewardsPlusRefund');
    assertEq(exit10.teamPlusBackersRewards(), 0, 'setup teamPlusBackersRewards');

    assertTrue(!exit10.inExitMode(), 'Check inExitMode');

    assertEq(address(exit10.EXIT()), address(exit), 'setup EXIT');
    assertEq(address(exit10.BLP()), address(blp), 'setup BLP');
    assertEq(address(exit10.BOOT()), address(boot), 'setup BOOT');
    assertEq(address(exit10.STO()), address(sto), 'setup STO');
    assertEq(address(exit10.NFT()), address(nft), 'setup NFT');
    assertEq(exit10.MASTERCHEF(), address(masterchefExit), 'setup MASTERCHEF');
    assertEq(exit10.FEE_SPLITTER(), address(feeSplitter), 'setup FEE_SPLITTER');

    assertEq(exit10.DEPLOYMENT_TIMESTAMP(), block.timestamp, 'setup DEPLOYMENT_TIMESTAMP');
    assertEq(exit10.BOOTSTRAP_PERIOD(), bootstrapPeriod, 'setup bootstrapPeriod');
    assertEq(exit10.ACCRUAL_PARAMETER(), accrualParameter * 1e18, 'setup ACCRUAL_PARAMETER');
  }
}
