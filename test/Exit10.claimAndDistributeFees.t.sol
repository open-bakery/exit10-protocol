// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';
import './Exit10.t.sol';

contract Exit10_claimAndDistributeFeesTest is Exit10Test {
  function testClaimAndDistributeFees() public {
    _skipBootstrap();
    _createBond(10_000_000_000000, 10_000 ether);
    _generateFees(address(token0), address(token1), 100_000_000_000000);

    _checkBuckets(_getLiquidity(), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertGt(feesClaimed0, 0, 'Fees claimed 0 > 0');
    assertGt(feesClaimed1, 0, 'Fees claimed 1 > 0');

    _checkBalancesExit10(0, 0);
  }
}
