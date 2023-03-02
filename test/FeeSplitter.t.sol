// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import '../src/BaseToken.sol';
import '../src/FeeSplitter.sol';
import '../src/Masterchef.sol';
import '../src/interfaces/ISwapper.sol';

contract FeeSplitterTest is Test {
  BaseToken STO = new BaseToken('Share Token', 'STO');
  BaseToken BOOT = new BaseToken('Bootstrap Token', 'BOOT');
  BaseToken BLP = new BaseToken('Boosted LP', 'BLP');

  address USDC = vm.envAddress('USDC');
  address WETH = vm.envAddress('WETH');
  address swapper = vm.envAddress('SWAPPER');
  address public immutable TOKEN_IN = WETH;
  address public immutable TOKEN_OUT = USDC;

  address masterchef0 = address(new Masterchef(WETH, 2 weeks));
  address masterchef1 = address(new Masterchef(WETH, 2 weeks));
  FeeSplitter feeSplitter;

  function setUp() public {
    feeSplitter = new FeeSplitter(masterchef0, masterchef1, swapper);
    Masterchef(masterchef0).setRewardDistributor(address(feeSplitter));
    Masterchef(masterchef1).setRewardDistributor(address(feeSplitter));
    feeSplitter.setExit10(address(this));
    ERC20(USDC).approve(address(feeSplitter), type(uint256).max);
    ERC20(WETH).approve(address(feeSplitter), type(uint256).max);
  }

  function testSimulateCollectFees() public {
    uint256 pendingShare = 40;
    uint256 remainingShare = 60;
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    _dealTokens(amountTokenOut, amountTokenIn);
    _simulateCollectFees(pendingShare, remainingShare, amountTokenOut, amountTokenIn);
    _checkBuckets(40_000_000000, 4_000 ether, 60_000_000000, 6_000 ether);
    _checkBalances(amountTokenOut, amountTokenIn);
  }

  function testSwapper() public {
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    _dealTokens(amountTokenOut, amountTokenIn);
    ERC20(USDC).approve(swapper, type(uint256).max);
    ERC20(WETH).approve(swapper, type(uint256).max);
    ISwapper(swapper).swap(
      ISwapper.SwapParameters({
        recipient: address(this),
        tokenIn: TOKEN_OUT,
        tokenOut: TOKEN_IN,
        fee: 500,
        amountIn: 10_000_000000,
        slippage: 100,
        oracleSeconds: 60
      })
    );
    console.log(ERC20(TOKEN_IN).balanceOf(address(this)));
  }

  function _simulateCollectFees(
    uint256 _pendingBucket,
    uint256 _remainingBuckets,
    uint256 _amountTokenOut,
    uint256 _amountTokenIn
  ) internal {
    feeSplitter.collectFees(_pendingBucket, _remainingBuckets, _amountTokenOut, _amountTokenIn);
  }

  function _dealTokens(uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    deal(TOKEN_OUT, address(this), _amountTokenOut);
    deal(TOKEN_IN, address(this), _amountTokenIn);
  }

  function _checkBuckets(
    uint256 _pendingBucketTokenOut,
    uint256 _pendingBucketTokenIn,
    uint256 _remainingBucketsTokenOut,
    uint256 _remainingBucketsTokenIn
  ) internal {
    assertTrue(_pendingBucketTokenOut == feeSplitter.pendingBucketTokenOut(), 'Check pending bucket token out');
    assertTrue(_pendingBucketTokenIn == feeSplitter.pendingBucketTokenIn(), 'Check pending bucket token in');
    assertTrue(_remainingBucketsTokenOut == feeSplitter.remainingBucketsTokenOut(), 'Check remaining bucket token out');
    assertTrue(_remainingBucketsTokenIn == feeSplitter.remainingBucketsTokenIn(), 'Check remaining bucket token in');
  }

  function _checkBalances(uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    assertTrue(_amountTokenOut == ERC20(TOKEN_OUT).balanceOf(address(feeSplitter)), 'Check balance token out');
    assertTrue(_amountTokenIn == ERC20(TOKEN_IN).balanceOf(address(feeSplitter)), 'Check balance token in');
  }
}
