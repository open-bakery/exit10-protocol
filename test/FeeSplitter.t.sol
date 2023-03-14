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
  uint24 public immutable FEE = 500;

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
    Masterchef(masterchef0).add(10, address(0x01));
    Masterchef(masterchef1).add(10, address(0x01));
  }

  function testSimulateCollectFees() public {
    uint256 pendingShare = 40;
    uint256 remainingShare = 60;
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    _dealTokens(amountTokenOut, amountTokenIn);
    _simulateCollectFees(pendingShare, remainingShare, amountTokenOut, amountTokenIn);
    _checkBuckets(40_000_000000, 4_000 ether, 60_000_000000, 6_000 ether);
    _checkBalances(address(feeSplitter), amountTokenOut, amountTokenIn);
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
    assertTrue(ERC20(WETH).balanceOf(address(this)) > amountTokenIn);
  }

  function testUpdateFeesPartialSell() public {
    uint256 pendingShare = 4;
    uint256 remainingShare = 6;
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    uint256 exchangeAmount = 20_000_000000;
    _dealTokens(amountTokenOut, amountTokenIn);
    _simulateCollectFees(pendingShare, remainingShare, amountTokenOut, amountTokenIn);
    uint256 exchanged = feeSplitter.updateFees(exchangeAmount);

    uint256 pendingTokenOut = ((amountTokenOut / 10) * pendingShare) - ((exchangeAmount / 10) * pendingShare);
    uint256 remainingTokenOut = ((amountTokenOut / 10) * remainingShare) - ((exchangeAmount / 10) * remainingShare);
    _checkBuckets(pendingTokenOut, 0, remainingTokenOut, 0);
    _checkBalances(address(feeSplitter), amountTokenOut - exchangeAmount, 0);

    uint256 exchangedPending = (exchanged / 10) * pendingShare;
    uint256 pendingTokenIn = exchangedPending + (amountTokenIn / 10) * pendingShare;
    _checkBalances(masterchef0, 0, (pendingTokenIn / 10) * 4);
    _checkBalances(masterchef1, 0, (amountTokenIn + exchanged) - ERC20(TOKEN_IN).balanceOf(masterchef0));
  }

  function testUpdateFeesNoSell() public {
    uint256 pendingShare = 4;
    uint256 remainingShare = 6;
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    _dealTokens(amountTokenOut, amountTokenIn);
    _simulateCollectFees(pendingShare, remainingShare, amountTokenOut, amountTokenIn);
    feeSplitter.updateFees(0);
    _checkBuckets(40_000_000000, 0, 60_000_000000, 0);
    _checkBalances(address(feeSplitter), 100_000_000000, 0);

    uint256 pendingTokenIn = (amountTokenIn / 10) * pendingShare;
    uint256 mc0BalanceTokenIn = (pendingTokenIn / 10) * 4;
    _checkBalances(masterchef0, 0, mc0BalanceTokenIn);
    _checkBalances(masterchef1, 0, amountTokenIn - mc0BalanceTokenIn);
  }

  function testUpdateFeesFullSell() public {
    uint256 pendingShare = 4;
    uint256 remainingShare = 6;
    uint256 amountTokenOut = 100_000_000000;
    uint256 amountTokenIn = 10_000 ether;
    _dealTokens(amountTokenOut, amountTokenIn);
    _simulateCollectFees(pendingShare, remainingShare, amountTokenOut, amountTokenIn);
    uint256 exchanged = feeSplitter.updateFees(100_000_000_000000);
    _checkBuckets(0, 0, 0, 0);
    _checkBalances(address(feeSplitter), 0, 0);

    uint256 exchangedPending = (exchanged / 10) * pendingShare;
    uint256 pendingTokenIn = (amountTokenIn / 10) * pendingShare + exchangedPending;
    uint256 mc0BalanceTokenIn = (pendingTokenIn / 10) * 4;
    _checkBalances(masterchef0, 0, mc0BalanceTokenIn);
    _checkBalances(masterchef1, 0, exchanged + amountTokenIn - mc0BalanceTokenIn);
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

  function _checkBalances(address _target, uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    assertTrue(_amountTokenOut == ERC20(TOKEN_OUT).balanceOf(_target), 'Check balance token out');
    assertTrue(_amountTokenIn == ERC20(TOKEN_IN).balanceOf(_target), 'Check balance token in');
  }
}
