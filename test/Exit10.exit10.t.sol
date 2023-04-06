// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_exit10Test is ABaseExit10Test {
  function test_exit10_RevertIf_NotOutOfRange() public {
    _skipBootAndCreateBond();

    vm.expectRevert(bytes('EXIT10: Current Tick not below TICK_LOWER'));
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
    _eth10k();
    exit10.exit10();

    assertEq(exit.totalSupply(), exit.balanceOf(address(this)), 'Check exit totalSupply');
  }

  function test_exit10() public {
    exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getBuckets();

    _checkBalancesExit10(0, 0);

    _eth10k();
    uint128 liquidityBeforeExit = _getLiquidity();
    exit10.exit10();
    uint256 AcquiredUSD = _balance(token0, address(exit10)) + _balance(token0, address(sto));
    uint256 exitLiquidityPlusBootstrap = liquidityBeforeExit - reserve;
    uint256 exitBootstrapUSD = (bootstrap * AcquiredUSD) / exitLiquidityPlusBootstrap;
    uint256 exitLiquidityUSD = (AcquiredUSD - exitBootstrapUSD);
    uint256 share = exitLiquidityUSD / 10;

    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertEq(_getLiquidity() - pending, reserve, 'Check reserve amount');
    assertGt(_balance(token0, address(exit10)), 0, 'Check acquired USD > 0');
    assertEq(exit + bootstrap, exitLiquidityPlusBootstrap, 'Check Exit Bucket');
    assertEq(exit10.bootstrapRewardsPlusRefund(), exitBootstrapUSD + share, 'Check Bootstrap USD share amount');
    assertEq(exit10.teamPlusBackersRewards(), share * 2, 'Check team plus backers'); // 20%
    assertEq(AcquiredUSD - (exitBootstrapUSD + share * 3), exit10.exitTokenRewardsFinal(), 'Check exit liquidity');
    assertEq(_balance(token1, address(exit10)), 0, 'Check balance token1 == 0');
  }

  function test_exit10_backInRange_claimAndDistributeFees() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _generateFees(token0, token1, 100000_000000);
    _createBond();
    _eth10k();
    exit10.exit10();
    // Go back into range
    _swap(weth, usdc, 10_000 ether);
    _generateFees(token0, token1, 100000_000000);
    uint256 preBalance0 = _balance(token0, exit10.PROTOCOL_GUILD());
    uint256 preBalance1 = _balance(token1, exit10.PROTOCOL_GUILD());
    exit10.claimAndDistributeFees();

    assertGt(_balance(token0, exit10.PROTOCOL_GUILD()), preBalance0, 'Check balance0 Protocol Guild');
    assertGt(_balance(token1, exit10.PROTOCOL_GUILD()), preBalance1, 'Check balance0 Protocol Guild');
  }
}
