// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Exit10 } from '../src/Exit10.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract FuzzTest is ABaseExit10Test {
  uint256 minUSD = 10000;
  uint256 maxUSD = 1_000_000_000_000000;
  uint256 minETH = 1 gwei;
  uint256 maxETH = 100_000_000 ether;

  function testFuzz_bootstrapLock(uint256 depositAmount0, uint256 depositAmount1) public {
    depositAmount0 = bound(depositAmount0, minUSD, maxUSD);
    depositAmount1 = bound(depositAmount0, minETH, maxETH);
    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(_addLiquidityParams(depositAmount0, depositAmount1));

    assertEq(_balance(boot), liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'Check BOOT balance');
    _checkBuckets(0, 0, 0, liquidityAdded);
  }

  function testFuzz_createBond(uint256 depositAmount0, uint256 depositAmount1) public {
    depositAmount0 = bound(depositAmount0, minUSD, maxUSD);
    depositAmount1 = bound(depositAmount0, minETH, maxETH);
    _skipBootstrap();
    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond(
      _addLiquidityParams(depositAmount0, depositAmount1)
    );

    assertEq(_getLiquidity(), liquidityAdded, 'Liquidity added returned');
    _checkBondData(bondId, _getLiquidity(), 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    assertGt(_getLiquidity(), 0, 'Check liquidity');
    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');

    _checkBalancesExit10(0, 0);
    _checkBalances(initialBalance - amountAdded0, initialBalance - amountAdded1);
    _checkBuckets(_getLiquidity(), 0, 0, 0);
  }

  function testFuzz_exit10(
    uint256 bootstrapDeposit0,
    uint256 bootstrapDeposit1,
    uint256 deposit0,
    uint256 deposit1
  ) public {
    bootstrapDeposit0 = bound(bootstrapDeposit0, minUSD, maxUSD);
    bootstrapDeposit1 = bound(bootstrapDeposit1, minETH, maxETH);
    deposit0 = bound(deposit0, minUSD, maxUSD);
    deposit1 = bound(deposit1, minETH, maxETH);
    _skipBootAndCreateBond(bootstrapDeposit0, bootstrapDeposit1, deposit0, deposit1);
    _eth10k();
    exit10.exit10();
  }

  function testFuzz_calculateShare(uint128 part, uint128 total, uint128 externalSum) public pure {
    _calcShare(part, total, externalSum);
  }

  function _calcShare(uint256 _part, uint256 _total, uint256 _externalSum) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }
}
