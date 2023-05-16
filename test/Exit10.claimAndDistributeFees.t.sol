// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_claimAndDistributeFeesTest is ABaseExit10Test {
  function testClaimAndDistributeFees() public {
    _skipBootstrap();
    _createBond();
    _generateFees(address(token0), address(token1), _tokenAmount(address(token0), 1000));

    _checkBuckets(_getLiquidity(), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertGt(feesClaimed0, 0, 'Fees claimed 0 > 0');
    assertGt(feesClaimed1, 0, 'Fees claimed 1 > 0');

    _checkBalancesExit10(0, 0);
  }

  function testClaimAndDistributeFees_minimumFees_NoRevert() public {
    _skipBootstrap();
    _createBond();
    _generateFees(address(token0), address(token1), _tokenAmount(address(token0), 1000));
    _checkBuckets(_getLiquidity(), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertGt(feesClaimed0, 0, 'Fees claimed 0 > 0');
    assertGt(feesClaimed1, 0, 'Fees claimed 1 > 0');

    _checkBalancesExit10(0, 0);
  }

  function testClaimAndDistributeFees_noFees_NoRevert() public {
    _skipBootstrap();
    _createBond();
    _checkBuckets(_getLiquidity(), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertEq(feesClaimed0, 0, 'Fees claimed 0 == 0');
    assertEq(feesClaimed1, 0, 'Fees claimed 1 == 0');

    _checkBalancesExit10(0, 0);
  }
}
