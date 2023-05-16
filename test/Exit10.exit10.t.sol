// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_exit10Test is ABaseExit10Test {
  function test_exit10_RevertIf_NotOutOfRange() public {
    _skipBootAndCreateBond();

    vm.expectRevert(bytes('EXIT10: Not out of tick range'));
    exit10.exit10();
  }

  function test_exit10_RevertIf_NoLiquidity() public {
    _skipBootstrap();
    _eth10k();
    vm.expectRevert(bytes('ERC721: operator query for nonexistent token'));
    exit10.exit10();
  }

  function test_exit10_RevertIf_AlreadyExited10() public {
    _skipToExit();

    vm.expectRevert(bytes('EXIT10: In Exit mode'));
    exit10.exit10();
  }

  function test_exit10_RevertIf_NoBootstrapNoBonds() public {
    _eth10k();

    vm.expectRevert();
    exit10.exit10();
  }

  function test_exit10_claimAndDistributeFees() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _generateFees(token0, token1, 100000_000000);
    _eth10k();

    exit10.exit10();

    assertGt(_balance(token0, feeSplitter), 0, 'Check balance0 feeSplitter');
    assertGt(_balance(token1, feeSplitter), 0, 'Check balance1 feeSplitter');
  }

  function test_exit10_burnExitRewards() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    uint256 blockTime = block.timestamp;
    _eth10k();
    uint256 distributedRewards = ((block.timestamp - blockTime) * masterchefExit.rewardRate()) /
      masterchefExit.PRECISION();
    exit10.exit10();
    assertEq(exit.totalSupply(), exit.balanceOf(address(this)) + distributedRewards, 'Check exit totalSupply');
  }

  function test_exit10() public {
    address tokenOut = exit10.TOKEN_OUT();
    address tokenIn = exit10.TOKEN_IN();

    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getBuckets();

    _checkBalancesExit10(0, 0);

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

  function test_exit10_backInRange_claimAndDistributeFees() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _generateFees(token0, token1, _tokenAmount(address(token0), 100_000));
    _createBond();
    _eth10k();
    exit10.exit10();
    // Go back into range
    uint256 saleAmount = _tokenAmount(address(token1), 10_000);
    deal(address(token1), address(this), saleAmount);
    _maxApprove(address(token1), address(UNISWAP_V3_ROUTER));
    _swap(address(token1), address(token0), saleAmount);
    _generateFees(token0, token1, _tokenAmount(address(token0), 100_000));
    uint256 preBalance0 = _balance(token0, exit10.BENEFICIARY());
    uint256 preBalance1 = _balance(token1, exit10.BENEFICIARY());
    exit10.claimAndDistributeFees();

    assertGt(_balance(token0, exit10.BENEFICIARY()), preBalance0, 'Check balance0 Protocol Guild');
    assertGt(_balance(token1, exit10.BENEFICIARY()), preBalance1, 'Check balance0 Protocol Guild');
  }
}
