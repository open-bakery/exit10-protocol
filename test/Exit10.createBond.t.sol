// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10_createBondTest is ABaseExit10Test {
  function test_createBond_RevertIf_BootstrapOngoing() public {
    vm.expectRevert(bytes('EXIT10: Bootstrap ongoing'));
    _createBond();
  }

  function test_createBond_RevertIf_Exited() public {
    _skipToExit();
    vm.expectRevert(bytes('EXIT10: In Exit mode'));
    _createBond();
  }

  function test_createBond() public {
    _skipBootstrap();
    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond(
      _addLiquidityParams(amount0, amount1)
    );

    assertEq(_getLiquidity(), liquidityAdded, 'Liquidity added returned');
    _checkBondData(bondId, _getLiquidity(), 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    assertGt(_getLiquidity(), 0, 'Check liquidity');
    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');

    _checkBalancesExit10(0, 0);
    _checkBalances(initialBalance - amountAdded0, initialBalance - amountAdded1);
    _checkBuckets(_getLiquidity(), 0, 0, 0);
  }

  function test_createBond_WithEther() public {
    _skipBootstrap();

    uint256 beforeBalance0 = _balance0();
    uint256 beforeBalance1 = _balance1();

    (uint256 depositToken0, uint256 depositToken1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), uint256(0))
      : (uint256(0), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));

    uint256 etherAmount = 10 ether;

    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{
      value: etherAmount
    }(_addLiquidityParams(depositToken0, depositToken1));

    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');

    if (exit10.TOKEN_OUT() < exit10.TOKEN_IN()) {
      assertEq(amountAdded0, beforeBalance0 - _balance0(), 'Check amountAdded0');
      assertGt(amountAdded1, 0, 'Check amountAdded1');
      _checkBalances(beforeBalance0 - amountAdded0, beforeBalance1 + etherAmount - amountAdded1);
    } else {
      assertGt(amountAdded0, 0, 'Check amountAdded0');
      assertEq(amountAdded1, beforeBalance1 - _balance1(), 'Check amountAdded1');
      _checkBalances(beforeBalance0 + etherAmount - amountAdded0, beforeBalance1 - amountAdded1);
    }

    _checkBondData(bondId, liquidityAdded, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    _checkBalancesExit10(0, 0);
    _checkBuckets(liquidityAdded, 0, 0, 0);
  }

  function test_createBond_WithEtherAndWeth() public {
    _skipBootstrap();

    uint256 beforeBalance0 = _balance0();
    uint256 beforeBalance1 = _balance1();

    (uint256 depositToken0, uint256 depositToken1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000), _tokenAmount(exit10.TOKEN_IN(), 5))
      : (_tokenAmount(exit10.TOKEN_IN(), 5), _tokenAmount(exit10.TOKEN_OUT(), 10_000));

    uint256 etherAmount = 10 ether;

    uint256 initialEthBalance = address(this).balance;

    (, , uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{ value: etherAmount }(
      _addLiquidityParams(depositToken0, depositToken1)
    );

    assertEq(address(this).balance, initialEthBalance - etherAmount, 'ETH balance after');

    if (exit10.TOKEN_OUT() < exit10.TOKEN_IN()) {
      assertEq(amountAdded0, beforeBalance0 - _balance0(), 'Check amountAdded0');
      assertEq(amountAdded1, (beforeBalance1 + etherAmount) - _balance1(), 'Check amountAdded1');
      assertEq(_balance1(), beforeBalance1 + etherAmount - amountAdded1, 'Check balance WETH after');
    } else {
      assertEq(amountAdded0, (beforeBalance0 + etherAmount) - _balance0(), 'Check amountAdded0');
      assertEq(amountAdded1, beforeBalance1 - _balance1(), 'Check amountAdded1');
      assertEq(_balance0(), beforeBalance0 + etherAmount - amountAdded0, 'Check balance WETH after');
    }
  }

  function test_createBond_OnBehalfOfUser() public {
    _skipBootstrap();

    (uint256 bondId, , , ) = exit10.createBond(
      UniswapBase.AddLiquidity({
        depositor: address(0xdead),
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertEq(nft.ownerOf(bondId), address(0xdead), 'Check NFT owner');
  }

  function test_createBond_WithBootstrap() public {
    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
    _skipBootstrap();

    (uint256 bondId, ) = _createBond(amount0, amount1);

    _checkBondData(bondId, _getLiquidity() - liquidityAdded, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    assertGt(_getLiquidity(), 0, 'Check liquidity');
    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');
    _checkBalancesExit10(0, 0);
    _checkBuckets(uint256(_getLiquidity()) - liquidityAdded, 0, 0, liquidityAdded);
  }

  function test_createBond_claimAndDistributeFees() public {
    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
    _skipBootstrap();
    _createBond(amount0, amount1);
    _generateFees(token0, token1, _tokenAmount(address(token0), 100_000));
    _createBond(amount0, amount1);
    assertGt(_balance(token0, feeSplitter), 0, 'Check balance0 feeSplitter');
    assertGt(_balance(token1, feeSplitter), 0, 'Check balance1 feeSplitter');
  }
}
