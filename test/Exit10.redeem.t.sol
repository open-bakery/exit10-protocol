// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';
import './Exit10.t.sol';

contract Exit10_redeemTest is Exit10Test {
  function test_redeem() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    uint128 liquidityToRemove = uint128(exit10.BLP().balanceOf(address(this)) / exit10.TOKEN_MULTIPLIER());

    exit10.redeem(_removeLiquidityParams(liquidityToRemove));

    assertGt(_balance0(), balanceToken0, 'Check balance token0');
    assertGt(_balance1(), balanceToken1, 'Check balance token1');
    assertEq(_balance(exit10.BLP()), 0, 'Check balance BLP');
    _checkBalancesExit10(0, 0);
    _checkBuckets(0, 0, __liquidity(), 0);
  }

  function test_redeem_ZeroAmount() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    vm.expectRevert();
    exit10.redeem(_removeLiquidityParams(0));
  }
}
