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
    if (exit10.TOKEN_IN() < exit10.TOKEN_OUT()) {
      (depositAmount0, depositAmount1) = (depositAmount1, depositAmount0);
    }

    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(_addLiquidityParams(depositAmount0, depositAmount1));

    assertEq(_balance(boot), liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'Check BOOT balance');
    _checkBuckets(0, 0, 0, liquidityAdded);
  }

  function testFuzz_createBond(uint256 depositAmount0, uint256 depositAmount1) public {
    depositAmount0 = bound(depositAmount0, minUSD, maxUSD);
    depositAmount1 = bound(depositAmount0, minETH, maxETH);
    if (exit10.TOKEN_IN() < exit10.TOKEN_OUT()) {
      (depositAmount0, depositAmount1) = (depositAmount1, depositAmount0);
    }

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

  function testFuzz_ConvertBond(uint256 deposit0, uint256 deposit1) public {
    deposit0 = bound(deposit0, minUSD, maxUSD);
    deposit1 = bound(deposit1, minETH, maxETH);
    if (exit10.TOKEN_IN() < exit10.TOKEN_OUT()) {
      (deposit0, deposit1) = (deposit1, deposit0);
    }

    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond(deposit0, deposit1);
    uint64 startTime = uint64(block.timestamp);
    uint256 liquidity = _getLiquidity();
    skip(accrualParameter); // skips to half

    uint256 accruedAmount = exit10.getAccruedAmount(bondId);
    uint256 exitSupply = exit.totalSupply();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    uint64 endTime = uint64(block.timestamp);
    uint256 exitBucket = _getLiquidity() - (liquidity / 2);

    assertEq(_balance(blp), (liquidity / 2) * exit10.TOKEN_MULTIPLIER(), 'BLP balance');
    uint256 exitBalance = _getExitAmount(liquidity - accruedAmount) + exitSupply > exit10.MAX_EXIT_SUPPLY()
      ? exit10.MAX_EXIT_SUPPLY() - exitSupply
      : _getExitAmount(liquidity - accruedAmount);
    assertEq(_balance(exit), exitBalance, 'Check exit bucket');
    assertEq(_balance(blp), (liquidity / 2) * exit10.TOKEN_MULTIPLIER(), 'BLP balance');
    _checkBalancesExit10(0, 0);
    _checkBondData(
      bondId,
      liquidity,
      (liquidity / 2) * exit10.TOKEN_MULTIPLIER(),
      startTime,
      endTime,
      uint8(Exit10.BondStatus.converted)
    );
    _checkBuckets(0, liquidity / 2, exitBucket, 0);
  }

  function testSuperFuzz_redeem(uint256 deposit0, uint256 deposit1) public {
    deposit0 = bound(deposit0, minUSD, maxUSD);
    deposit1 = bound(deposit1, minETH, maxETH);
    if (exit10.TOKEN_IN() < exit10.TOKEN_OUT()) {
      (deposit0, deposit1) = (deposit1, deposit0);
    }

    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond(deposit0, deposit1);
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    uint128 liquidityToRemove = uint128(exit10.BLP().balanceOf(address(this)) / exit10.TOKEN_MULTIPLIER());
    exit10.redeem(_removeLiquidityParams(liquidityToRemove));
    assertTrue(_balance0() != balanceToken0 || _balance1() != balanceToken1, 'Check tokens balance');
    assertEq(_balance(blp), 0, 'Check balance BLP');
    _checkBalancesExit10(0, 0);
    _checkBuckets(0, 0, _getLiquidity(), 0);
  }

  function testFuzz_exit10(
    uint256 bootstrapDeposit0,
    uint256 bootstrapDeposit1,
    uint256 deposit0,
    uint256 deposit1
  ) public {
    address tokenOut = exit10.TOKEN_OUT();
    address tokenIn = exit10.TOKEN_IN();
    bootstrapDeposit0 = bound(bootstrapDeposit0, minUSD, maxUSD);
    bootstrapDeposit1 = bound(bootstrapDeposit1, minETH, maxETH);
    deposit0 = bound(deposit0, minUSD, maxUSD);
    deposit1 = bound(deposit1, minETH, maxETH);
    if (tokenIn < tokenOut) {
      (bootstrapDeposit0, bootstrapDeposit1) = (bootstrapDeposit1, bootstrapDeposit0);
      (deposit0, deposit1) = (deposit1, deposit0);
    }

    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond(
      bootstrapDeposit0,
      bootstrapDeposit1,
      deposit0,
      deposit1
    );
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getBuckets();

    _eth10k();
    uint128 liquidityBeforeExit = _getLiquidity();
    exit10.exit10();

    uint256 acquiredTokenOut = _balance(tokenOut, address(exit10));
    uint256 exitLiquidityPlusBootstrapDeposits = liquidityBeforeExit - reserve;
    uint256 exitBootstrapDepositsTokenOut = (bootstrap * acquiredTokenOut) / exitLiquidityPlusBootstrapDeposits;
    uint256 exitLiquidityTokenOut = (acquiredTokenOut - exitBootstrapDepositsTokenOut);
    uint256 share = exitLiquidityTokenOut / 10;

    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertEq(exit + bootstrap, exitLiquidityPlusBootstrapDeposits, 'Check Exit Bucket');
    assertEq(_getLiquidity() - pending, reserve, 'Check reserve amount');
    assertGt(_balance(tokenOut, address(exit10)), 0, 'Check acquired TOKEN_OUT > 0');

    assertEq(
      exit10.bootstrapRewardsPlusRefund(),
      exitBootstrapDepositsTokenOut + share,
      'Check Bootstrap TOKEN_OUT share amount'
    );
    assertEq(exit10.teamPlusBackersRewards(), share * 2, 'Check team plus backers'); // 20%
    assertEq(
      acquiredTokenOut - (exitBootstrapDepositsTokenOut + share * 3),
      exit10.exitTokenRewardsFinal(),
      'Check exit liquidity'
    );
    assertEq(_balance(tokenIn, address(exit10)), 0, 'Check balance TOKEN_IN == 0');
  }

  function testFuzz_claims(
    uint256 stoAmount,
    uint256 bootstrapDeposit0,
    uint256 bootstrapDeposit1,
    uint256 deposit0,
    uint256 deposit1
  ) public {
    stoAmount = bound(stoAmount, minETH, sto.MAX_SUPPLY());
    bootstrapDeposit0 = bound(bootstrapDeposit0, minUSD, maxUSD);
    bootstrapDeposit1 = bound(bootstrapDeposit1, minETH, maxETH);
    deposit0 = bound(deposit0, minUSD, maxUSD);
    deposit1 = bound(deposit1, minETH, maxETH);
    if (exit10.TOKEN_IN() < exit10.TOKEN_OUT()) {
      (bootstrapDeposit0, bootstrapDeposit1) = (bootstrapDeposit1, bootstrapDeposit0);
      (deposit0, deposit1) = (deposit1, deposit0);
    }

    deal(address(sto), address(this), stoAmount);
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond(
      bootstrapDeposit0,
      bootstrapDeposit1,
      deposit0,
      deposit1
    );
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _eth10k();
    exit10.exit10();

    assertGt(exit.balanceOf(address(this)), 0, 'Check balance exit > 0');
    assertGt(boot.balanceOf(address(this)), 0, 'Check balance boot > 0');
    assertGt(sto.balanceOf(address(this)), 0, 'Check balance sto > 0');

    exit10.exitClaim();
    exit10.bootstrapClaim();
    exit10.stoClaim();

    assertEq(exit.balanceOf(address(this)), 0, 'Check balance exit');
    assertEq(boot.balanceOf(address(this)), 0, 'Check balance boot');
    assertEq(sto.balanceOf(address(this)), 0, 'Check balance sto');
  }

  function testFuzz_calculateShare(uint128 part, uint128 total, uint128 externalSum) public pure {
    _calcShare(part, total, externalSum);
  }

  function _calcShare(uint256 _part, uint256 _total, uint256 _externalSum) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }
}
