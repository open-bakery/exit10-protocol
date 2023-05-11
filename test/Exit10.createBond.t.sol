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
      _addLiquidityParams(10000_000000, 10 ether)
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
    uint256 depositToken0 = _tokenAmount(token0, 10_000);
    uint256 depositToken1 = 10 ether;
    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{
      value: depositToken1
    }(_addLiquidityParams(depositToken0, 0));
    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');
    assertEq(amountAdded0, initialBalance - _balance0(), 'Check amountAdded0');
    assertEq(amountAdded1, depositToken1 - (_balance1() - initialBalance), 'Check amountAdded1');

    _checkBondData(bondId, liquidityAdded, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    _checkBalances(initialBalance - amountAdded0, initialBalance - amountAdded1 + depositToken1);
    _checkBalancesExit10(0, 0);
    _checkBuckets(liquidityAdded, 0, 0, 0);
  }

  function test_createBond_WithEtherAndWeth() public {
    _skipBootstrap();
    uint256 depositToken0 = _tokenAmount(token0, 10_000);
    uint256 depositToken1 = 5 ether;
    uint256 depositEther = 10 ether;
    uint256 initialEthBalance = address(this).balance;

    (, , uint256 amountAdded0, uint256 amountAdded1) = exit10.createBond{ value: depositEther }(
      _addLiquidityParams(depositToken0, depositToken1)
    );

    assertEq(address(this).balance, initialEthBalance - 10 ether, 'ETH balance after');
    assertEq(_balance1(), initialBalance + 10 ether - amountAdded1, 'WETH balance after');
    assertEq(amountAdded0, initialBalance - _balance0(), 'Check amountAdded0');
    assertEq(amountAdded1, (initialBalance + depositEther) - _balance1(), 'Check amountAdded1');
  }

  function test_createBond_OnBehalfOfUser() public {
    _skipBootstrap();

    (uint256 bondId, , , ) = exit10.createBond(
      UniswapBase.AddLiquidity({
        depositor: address(0xdead),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertEq(nft.ownerOf(bondId), address(0xdead), 'Check NFT owner');
  }

  function test_createBond_WithBootstrap() public {
    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
    _skipBootstrap();

    (uint256 bondId, ) = _createBond(10000_000000, 10 ether);

    _checkBondData(bondId, _getLiquidity() - liquidityAdded, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
    assertGt(_getLiquidity(), 0, 'Check liquidity');
    assertEq(nft.ownerOf(bondId), address(this), 'Check NFT owner');
    _checkBalancesExit10(0, 0);
    _checkBuckets(uint256(_getLiquidity()) - liquidityAdded, 0, 0, liquidityAdded);
  }

  function test_createBond_claimAndDistributeFees() public {
    exit10.bootstrapLock(_addLiquidityParams(1000000_000000, 1000 ether));
    _skipBootstrap();
    _createBond(10000_000000, 10 ether);
    _generateFees(token0, token1, 100000_000000);
    _createBond(10000_000000, 10 ether);
    assertGt(_balance(token0, feeSplitter), 0, 'Check balance0 feeSplitter');
    assertGt(_balance(token1, feeSplitter), 0, 'Check balance1 feeSplitter');
  }
}
