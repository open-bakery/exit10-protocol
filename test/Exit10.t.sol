// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10Test is Test, ABaseExit10Test {
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
    assertEq(exit10.exitTokenRewardsClaimed(), 0, 'setup exitTokenRewardsClaimed');
    assertEq(exit10.bootstrapRewardsPlusRefund(), 0, 'setup bootstrapRewardsPlusRefund');
    assertEq(exit10.bootstrapRewardsPlusRefundClaimed(), 0, 'setup bootstrapRewardsPlusRefundClaimed');
    assertEq(exit10.teamPlusBackersRewards(), 0, 'setup teamPlusBackersRewards');
    assertEq(exit10.teamPlusBackersRewardsClaimed(), 0, 'setup teamPlusBackersRewardsClaimed');
    assertEq(exit10.teamPlusBackersRewardsClaimed(), 0, 'setup teamPlusBackersRewardsClaimed');

    assertTrue(!exit10.inExitMode(), 'Check inExitMode');

    assertEq(address(exit10.EXIT()), address(exit), 'setup EXIT');
    assertEq(address(exit10.BLP()), address(blp), 'setup BLP');
    assertEq(address(exit10.BOOT()), address(boot), 'setup BOOT');
    assertEq(address(exit10.STO()), address(sto), 'setup STO');
    assertEq(address(exit10.NFT()), address(nft), 'setup NFT');
    assertEq(exit10.MASTERCHEF(), address(masterchefExit), 'setup MASTERCHEF');
    assertEq(exit10.FEE_SPLITTER(), address(feeSplitter), 'setup FEE_SPLITTER');

    assertEq(exit10.DEPLOYMENT_TIMESTAMP(), block.timestamp, 'setup DEPLOYMENT_TIMESTAMP');
    assertEq(exit10.BOOTSTRAP_PERIOD(), bootstrapPeriod, 'setup BOOTSTRAP_PERIOD');
    assertEq(exit10.ACCRUAL_PARAMETER(), accrualParameter * 1e18, 'setup ACCRUAL_PARAMETER');
    assertEq(exit10.LP_PER_USD(), lpPerUSD, 'setup LP_PER_USD');
  }

  function testAccrualSchedule() public {
    (uint256 bondId, ) = _skipBootAndCreateBond();
    skip(accrualParameter);
    assertTrue(exit10.getAccruedAmount(bondId) == _liquidity() / 2);
  }
}
