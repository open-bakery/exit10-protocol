// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10_getAccruedAmountTest is ABaseExit10Test {
  function test_getAccruedAmount() public {
    (uint256 bondId, ) = _skipBootAndCreateBond();
    uint256 bondAmount = _getLiquidity();
    skip(100);
    assertEq(exit10.getAccruedAmount(bondId), (bondAmount * 100) / (100 + accrualParameter));
    skip(500);
    assertEq(exit10.getAccruedAmount(bondId), (bondAmount * 600) / (600 + accrualParameter));
    skip(387);
    assertEq(exit10.getAccruedAmount(bondId), (bondAmount * 987) / (987 + accrualParameter));
  }
}
