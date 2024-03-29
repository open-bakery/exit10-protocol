// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10 } from '../src/Exit10.sol';

contract Exit10_cancelBondTest is ABaseExit10Test {
  function test_cancelBond() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();

    uint256 liquidity = _getLiquidity();
    uint256 startTime = block.timestamp;
    skip(1 days);
    uint256 endTime = block.timestamp;
    uint256 balanceBefore0 = _balance0();
    uint256 balanceBefore1 = _balance1();

    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));

    assertEq(_getLiquidity(), 0, 'Check liquidity');
    assertGt(_balance0(), balanceBefore0, 'Check balance token0');
    assertGt(_balance1(), balanceBefore1, 'Check balance token1');
    _checkBalancesExit10(0, 0);
    _checkBondData(bondId, liquidity, 0, startTime, endTime, uint8(Exit10.BondStatus.cancelled));
    _checkBuckets(0, 0, 0, 0);
  }

  function test_cancelBond_withMoreBondsInTheSystem() public {
    _skipBootAndCreateBond();
    _createBond(alice);
    _createBond(bob);
    (uint256 bondId, uint256 bondAmount) = _createBond(charlie);
    uint256 liquidity = _getLiquidity();
    uint256 startTime = block.timestamp;
    skip(1 days);
    uint256 endTime = block.timestamp;
    uint256 balanceBefore0 = _balance(token0, charlie);
    uint256 balanceBefore1 = _balance(token1, charlie);
    vm.prank(charlie);
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));
    _checkBondData(bondId, bondAmount, 0, startTime, endTime, uint8(Exit10.BondStatus.cancelled));
    assertEq(_getLiquidity(), liquidity - bondAmount, 'Check liquidity');
    assertGt(_balance(token0, charlie), balanceBefore0, 'Check balance token0');
    assertGt(_balance(token1, charlie), balanceBefore1, 'Check balance token1');
  }

  function test_cancelBond_claimAndDistributeFees() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    _generateFees(token0, token1, _tokenAmount(address(token0), 100000));
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));
    assertGt(_balance(token0, feeSplitter), 0, 'Check balance0 feeSplitter');
    assertGt(_balance(token1, feeSplitter), 0, 'Check balance1 feeSplitter');
  }

  function test_cancelBond_RevertIf_NotBondOwner() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    vm.prank(address(0xdead));

    vm.expectRevert(bytes('EXIT10: Caller must own the bond'));
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));
  }

  function test_cancelBond_RevertIf_StatusIsCanceled() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));

    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));
  }

  function test_cancelBond_RevertIf_StatusIsConverted() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));
  }
}
