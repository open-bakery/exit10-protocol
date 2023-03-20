// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { IExit10, IUniswapBase } from '../src/Exit10.sol';
import { DepositHelper } from '../src/DepositHelper.sol';
import { IUniswapV3Router } from '../src/interfaces/IUniswapV3Router.sol';

contract DepositHelperTest is Test, ABaseExit10Test {
  DepositHelper depositHelper;

  function setUp() public override {
    super.setUp();
    depositHelper = new DepositHelper(address(UNISWAP_V3_ROUTER), address(exit10), weth);
    _maxApprove(weth, address(depositHelper));
    _maxApprove(usdc, address(depositHelper));
  }

  function testSwapAndBootstrapLock() public {
    uint256 preBalanceEth = address(this).balance;
    uint256 initialAmount0 = _tokenAmount(usdc, 10000);
    uint256 sellAmount0 = _tokenAmount(usdc, 1000);
    uint256 initialAmount1 = _tokenAmount(weth, 2);
    uint256 etherAmount = 4 ether;
    IUniswapV3Router.ExactInputSingleParams memory swapParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: usdc,
      tokenOut: weth,
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: sellAmount0,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = depositHelper
      .swapAndBootstrapLock{ value: etherAmount }(initialAmount0, initialAmount1, swapParams);

    _checkBalances(address(depositHelper), usdc, weth, 0, 0);
    _checkBuckets(exit10, 0, 0, 0, liquidityAdded);

    assertTrue(_liquidity(tokenId, exit10) == liquidityAdded, 'Check position created');
    assertTrue(
      ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * exit10.TOKEN_MULTIPLIER(),
      'Check liquidity equals boot amount'
    );
    assertTrue(address(this).balance == preBalanceEth - etherAmount, 'Check Eth deposit');
    assertTrue(amountAdded1 != 0, 'Check amount1 added');
    assertTrue(amountAdded0 != 0, 'Check amount0 added');
    assertTrue(ERC20(exit10.BOOT()).balanceOf(address(this)) != 0, 'Check balance BOOT');
    assertTrue(ERC20(weth).balanceOf(address(this)) != 0, 'Check balance weth');
  }

  function testSwapAndCreateBond() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 preBalanceEth = address(this).balance;
    uint256 initialAmount0 = _tokenAmount(usdc, 10000);
    uint256 sellAmount0 = _tokenAmount(usdc, 1000);
    uint256 initialAmount1 = _tokenAmount(weth, 2);
    uint256 etherAmount = 4 ether;
    IUniswapV3Router.ExactInputSingleParams memory swapParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: usdc,
      tokenOut: weth,
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: sellAmount0,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    (uint256 bondId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = depositHelper
      .swapAndCreateBond{ value: etherAmount }(initialAmount0, initialAmount1, swapParams);

    _checkBalances(address(depositHelper), usdc, weth, 0, 0);
    _checkBuckets(exit10, liquidityAdded, 0, 0, 0);
    _checkBondData(exit10, bondId, liquidityAdded, 0, uint64(block.timestamp), 0, uint8(IExit10.BondStatus.active));

    assertTrue(_liquidity(exit10.positionId(), exit10) == liquidityAdded, 'Check position created');
    assertTrue(address(this).balance == preBalanceEth - etherAmount, 'Check Eth deposit');
    assertTrue(amountAdded1 != 0, 'Check amount1 added');
    assertTrue(amountAdded0 != 0, 'Check amount0 added');
    assertTrue(IERC721(exit10.NFT()).balanceOf(address(this)) == 1, 'Check balance NFT');
    assertTrue(ERC20(weth).balanceOf(address(this)) != 0, 'Check balance weth');
  }
}
