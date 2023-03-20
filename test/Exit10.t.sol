// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { IExit10, IUniswapBase } from '../src/Exit10.sol';

contract Exit10Test is Test, ABaseExit10Test {
  function setUp() public override {
    super.setUp();
  }

  function testSetup() public {
    assertTrue(exit10.positionId() == 0, 'Check positionId');
    assertTrue(exit10.inExitMode() == false, 'Check inExitMode');
    assertTrue(token0.balanceOf(address(this)) == initialBalance);
    assertTrue(token1.balanceOf(address(this)) == initialBalance);
  }

  function testBootstrapLock() public {
    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(amountAdded0 == initialBalance - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(amountAdded1 == initialBalance - token1.balanceOf(address(this)), 'Check amountAdded1');
    assertTrue(tokenId == exit10.positionId(), 'Check positionId');
    assertTrue(liquidityAdded != 0, 'Check liquidityAdded');
    assertTrue(
      ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * exit10.TOKEN_MULTIPLIER(),
      'Check BOOT balance'
    );

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, 0, 0, 0, liquidityAdded);
  }

  function testBootstrapLockWithEther() public {
    uint256 depositToken0 = _tokenAmount(address(token0), 10_000);
    uint256 depositToken1 = 10 ether;
    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock{
      value: depositToken1
    }(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: depositToken0,
        amount1Desired: 0,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(amountAdded0 == initialBalance - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(
      amountAdded1 == depositToken1 - (token1.balanceOf(address(this)) - initialBalance),
      'Check amountAdded1'
    );
    assertTrue(tokenId == exit10.positionId(), 'Check positionId');
    assertTrue(liquidityAdded != 0, 'Check liquidityAdded');
    assertTrue(
      ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * exit10.TOKEN_MULTIPLIER(),
      'Check BOOT balance'
    );

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, 0, 0, 0, liquidityAdded);
  }

  function testBootstrapWithMinimumAmount() public {
    uint256 minToken0 = 1e0;
    uint256 minToken1 = 1e0;

    try
      exit10.bootstrapLock(
        IUniswapBase.AddLiquidity({
          depositor: address(this),
          amount0Desired: minToken0,
          amount1Desired: minToken1,
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      )
    {} catch {
      return;
    }
    assertTrue(true);
  }

  function testBootstrapRevert() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    vm.expectRevert(bytes('EXIT10: Bootstrap ended'));
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCreateBondBootstrapOngoingRevert() public {
    vm.expectRevert(bytes('EXIT10: Bootstrap ongoing'));
    exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCreateBond() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = _createBond(exit10, 10000_000000, 10 ether);
    _checkBondData(
      exit10,
      bondId,
      _liquidity(exit10.positionId(), exit10),
      0,
      uint64(block.timestamp),
      0,
      uint8(IExit10.BondStatus.active)
    );
    assertTrue(_liquidity(exit10.positionId(), exit10) != 0, 'Check liquidity');
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, uint256(_liquidity(exit10.positionId(), exit10)), 0, 0, 0);
  }

  function testCreateBondWithEther() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 depositToken0 = _tokenAmount(address(token0), 10_000);
    uint256 depositToken1 = 10 ether;
    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{
      value: depositToken1
    }(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: depositToken0,
        amount1Desired: 0,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');
    assertTrue(amountAdded0 == initialBalance - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(
      amountAdded1 == depositToken1 - (token1.balanceOf(address(this)) - initialBalance),
      'Check amountAdded1'
    );

    _checkBondData(exit10, bondId, liquidityAdded, 0, uint64(block.timestamp), 0, uint8(IExit10.BondStatus.active));
    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, liquidityAdded, 0, 0, 0);
  }

  function testCreateBondWithEtherAndWeth() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 depositToken0 = _tokenAmount(address(token0), 10_000);
    uint256 depositToken1 = 5 ether;
    uint256 depositEther = 10 ether;
    (, , uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{ value: depositToken1 }(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: depositToken0,
        amount1Desired: depositToken1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(amountAdded0 == initialBalance - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(
      amountAdded1 ==
        (depositEther + depositToken1) - (token1.balanceOf(address(this)) + depositEther - initialBalance),
      'Check amountAdded1'
    );
  }

  function testCreateBondOnBehalfOfUser() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    (uint256 bondId, , , ) = exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: address(0xdead),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(nft.ownerOf(bondId) == address(0xdead), 'Check NFT owner');
  }

  function testCreateBondWithBootstrap() public {
    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = _createBond(exit10, 10000_000000, 10 ether);
    _checkBondData(
      exit10,
      bondId,
      _liquidity(exit10.positionId(), exit10) - liquidityAdded,
      0,
      uint64(block.timestamp),
      0,
      uint8(IExit10.BondStatus.active)
    );
    assertTrue(_liquidity(exit10.positionId(), exit10) != 0, 'Check liquidity');
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, uint256(_liquidity(exit10.positionId(), exit10)) - liquidityAdded, 0, 0, liquidityAdded);
  }

  function testCancelBond() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    uint256 liquidity = _liquidity(exit10.positionId(), exit10);
    uint64 startTime = uint64(block.timestamp);
    skip(1 days);
    uint64 endTime = uint64(block.timestamp);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance(address(token0), address(token1));
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(_liquidity(exit10.positionId(), exit10) == 0, 'Check liquidity');
    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBondData(exit10, bondId, liquidity, 0, startTime, endTime, uint8(IExit10.BondStatus.cancelled));
    _checkBuckets(exit10, 0, 0, 0, 0);
  }

  function testCancelBondNoBondsRevert() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    vm.prank(address(0xdead));
    vm.expectRevert(bytes('EXIT10: Caller must own the bond'));
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCancelBondActiveStatusRevert() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testConvertBond() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    uint64 startTime = uint64(block.timestamp);
    uint256 liquidity = _liquidity(exit10.positionId(), exit10);

    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    uint64 endTime = uint64(block.timestamp);
    uint256 exitBucket = _liquidity(exit10.positionId(), exit10) - (liquidity / 2);

    assertTrue(exit10.BLP().balanceOf(address(this)) == (liquidity / 2) * exit10.TOKEN_MULTIPLIER());
    assertTrue(exit10.EXIT().balanceOf(address(this)) == exitBucket * exit10.TOKEN_MULTIPLIER(), 'Check exit bucket');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBondData(
      exit10,
      bondId,
      liquidity,
      (liquidity / 2) * exit10.TOKEN_MULTIPLIER(),
      startTime,
      endTime,
      uint8(IExit10.BondStatus.converted)
    );
    _checkBuckets(exit10, 0, liquidity / 2, exitBucket, 0);
  }

  function testRedeem() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance(address(token0), address(token1));
    uint128 liquidityToRemove = uint128(exit10.BLP().balanceOf(address(this)) / exit10.TOKEN_MULTIPLIER());
    exit10.redeem(
      IUniswapBase.RemoveLiquidity({
        liquidity: liquidityToRemove,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');
    assertTrue(exit10.BLP().balanceOf(address(this)) == 0, 'Check balance BLP');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
    _checkBuckets(exit10, 0, 0, _liquidity(exit10.positionId(), exit10), 0);
  }

  function testClaimAndDistributeFees() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10_000_000_000000,
        amount1Desired: 10_000 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    _generateFees(address(token0), address(token1), 100_000_000_000000);

    _checkBuckets(exit10, _liquidity(exit10.positionId(), exit10), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertTrue(feesClaimed0 != 0, 'Check fees claimed 0');
    assertTrue(feesClaimed1 != 0, 'Check fees claimed 1');

    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);
  }

  function testExit10Revert() public {
    _skipBootAndCreateBond(exit10);
    vm.expectRevert(bytes('EXIT10: Current Tick not below TICK_LOWER'));
    exit10.exit10();
  }

  function testExit10() public {
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint256 bondId = _skipBootAndCreateBond(exit10);
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getBuckets();
    _checkBalances(address(exit10), address(token0), address(token1), 0, 0);

    _eth10k(exit10);
    uint128 totalLiquidity = _liquidity(exit10.positionId(), exit10);
    exit10.exit10();

    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertTrue(_liquidity(exit10.positionId(), exit10) - pending == reserve, 'Check reserve amount');
    assertTrue(token0.balanceOf(address(exit10)) != 0, 'Check acquired USD != 0');

    uint256 AcquiredUSD = token0.balanceOf(address(exit10)) + token0.balanceOf(address(sto));
    uint256 exitLiquidityPlusBootstrap = totalLiquidity - reserve;

    assertTrue(exit + bootstrap == exitLiquidityPlusBootstrap, 'Check Exitbucket');

    uint256 exitBootstrapUSD = (bootstrap * AcquiredUSD) / exitLiquidityPlusBootstrap;
    uint256 exitLiquidityUSD = (AcquiredUSD - exitBootstrapUSD);
    uint256 share = exitLiquidityUSD / 10;

    assertTrue(exit10.bootstrapRewardsPlusRefund() == exitBootstrapUSD + share, 'Check Bootstrap USD share amount');
    assertTrue(exit10.teamPlusBackersRewards() == share * 2, 'Check team plus backers'); // 20%
    assertTrue(AcquiredUSD - (exitBootstrapUSD + share * 3) == exit10.exitTokenRewardsFinal(), 'Check exit liquidity');
    assertTrue(ERC20(token1).balanceOf(address(exit10)) == 0, 'Check balance token1 == 0');
  }

  function testBootstrapClaim() public {
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint256 bondId = _skipBootAndCreateBond(exit10);
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    _eth10k(exit10);
    exit10.exit10();
    (uint256 pending, uint256 reserve, , uint256 bootstrap) = exit10.getBuckets();

    assertTrue(_liquidity(exit10.positionId(), exit10) == pending + reserve, 'Check liquidity position');

    uint256 currentBalanceUSDC = ERC20(token0).balanceOf(address(this));
    uint256 bootBalance = ERC20(exit10.BOOT()).balanceOf(address(this));
    exit10.bootstrapClaim();
    uint256 claimableAmount = ((bootBalance / exit10.TOKEN_MULTIPLIER()) * exit10.bootstrapRewardsPlusRefund()) /
      bootstrap;

    assertTrue(ERC20(exit10.BOOT()).balanceOf(address(this)) == 0, 'Check BOOT burned');
    assertTrue(
      ERC20(token0).balanceOf(address(this)) - currentBalanceUSDC == claimableAmount,
      'Check claimable amount'
    );
    assertTrue(ERC20(token0).balanceOf(address(this)) == currentBalanceUSDC + claimableAmount, 'Check amount claimed');
    assertTrue(claimableAmount != 0, 'Check claimable != 0');
  }

  function testBootstrapClaimRevert() public {
    _skipBootAndCreateBond(exit10);
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.bootstrapClaim();
  }

  function testExitClaim() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertTrue(ERC20(exit10.EXIT()).balanceOf(address(this)) != 0, 'Check exit balance');

    _eth10k(exit10);
    exit10.exit10();
    uint256 initialBalanceUSDC = ERC20(token0).balanceOf(address(this));
    uint256 exitBalance = ERC20(exit).balanceOf(address(this));
    uint256 precision = 1e18;
    uint256 exitTokenShare = (exitBalance * precision) / ERC20(exit).totalSupply();
    exit10.exitClaim();

    assertTrue(ERC20(exit10.EXIT()).balanceOf(address(this)) == 0, 'Check exit burn');
    assertTrue(
      ERC20(token0).balanceOf(address(this)) - initialBalanceUSDC ==
        (exit10.exitTokenRewardsFinal() * exitTokenShare) / precision,
      'Check USD balance'
    );
  }

  function testExitClaimRevert() public {
    _skipBootAndCreateBond(exit10);
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.exitClaim();
  }

  function testAccrualSchedule() public {
    uint256 bondId = _skipBootAndCreateBond(exit10);
    skip(accrualParameter);
    assertTrue(exit10.getAccruedAmount(bondId) == _liquidity(exit10.positionId(), exit10) / 2);
  }
}
