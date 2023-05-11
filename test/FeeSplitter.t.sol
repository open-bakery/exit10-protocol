// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { console } from 'forge-std/console.sol';
import { BaseToken } from '../src/BaseToken.sol';
import { FeeSplitter } from '../src/FeeSplitter.sol';
import { Masterchef } from '../src/Masterchef.sol';
import { ISwapper } from '../src/interfaces/ISwapper.sol';
import { ABaseTest } from './ABase.t.sol';

contract FeeSplitterTest is ABaseTest {
  BaseToken STO = new BaseToken('Share Token', 'STO');
  BaseToken BOOT = new BaseToken('Bootstrap Token', 'BOOT');
  BaseToken BLP = new BaseToken('Boosted LP', 'BLP');

  address public USDC = vm.envAddress('USDC');
  address public WETH = vm.envAddress('WETH');
  address swapper = vm.envAddress('SWAPPER');
  address public immutable TOKEN_IN = WETH;
  address public immutable TOKEN_OUT = USDC;
  uint24 public immutable FEE = 500;

  FeeSplitter feeSplitter;
  address masterchef0;
  address masterchef1;

  uint32 constant ORACLE_SECONDS = 60;

  uint256 mc0Share = 4;
  uint256 pendingShare = 4;
  uint256 remainingShare = 6 + pendingShare;
  uint256 amountUsdc = _usdcAmount(100_000);
  uint256 amountWeth = 10_000 ether;

  function setUp() public {
    Masterchef mc0 = new Masterchef(WETH, 2 weeks);
    Masterchef mc1 = new Masterchef(WETH, 2 weeks);
    masterchef0 = address(mc0);
    masterchef1 = address(mc1);

    feeSplitter = new FeeSplitter(masterchef0, masterchef1, swapper);
    feeSplitter.setExit10(me); // = address(this)

    mc0.add(10, address(0x01));
    mc1.add(10, address(0x01));
    mc0.transferOwnership(address(feeSplitter));
    mc1.transferOwnership(address(feeSplitter));

    _maxApprove(USDC, WETH, address(feeSplitter));
  }

  function test_collectFees_RevertIf_NotAuthorized() public {
    vm.expectRevert(bytes('FeeSplitter: Caller not authorized'));
    vm.prank(bob);
    feeSplitter.collectFees(pendingShare, remainingShare, amountUsdc, amountWeth);
  }

  function test_collectFees() public {
    _dealTokens(amountUsdc, amountWeth);
    // note: using shares instead of values because in FeeSplitter.collectFees, only the ratio is used.
    feeSplitter.collectFees(pendingShare, remainingShare, amountUsdc, amountWeth);
    _checkBuckets(
      (amountUsdc * pendingShare) / 10,
      (amountWeth * pendingShare) / 10,
      (amountUsdc * (remainingShare - pendingShare)) / 10,
      (amountWeth * (remainingShare - pendingShare)) / 10
    );
    _checkBalances(address(feeSplitter), amountUsdc, amountWeth);
  }

  function test_collectFees_ZeroTokens() public {
    _dealTokens(amountUsdc, amountWeth);
    feeSplitter.collectFees(pendingShare, remainingShare, 0, 0);
    _checkBuckets(0, 0, 0, 0);
    _checkBalances(address(feeSplitter), 0, 0);
  }

  // note: not a super thorough swapper test. Just make sure it's working in this setup
  function test_Swapper() public {
    _dealTokens(amountUsdc, amountWeth);
    _maxApprove(USDC, WETH, swapper);
    skip(ORACLE_SECONDS);

    uint256 amountUsdcConvert = _usdcAmount(10_000);
    uint256 usdcBalanceBefore = _balance(USDC);

    ISwapper(swapper).swap(
      ISwapper.SwapParameters({
        recipient: me,
        tokenIn: USDC,
        tokenOut: WETH,
        fee: 500,
        amountIn: amountUsdcConvert,
        slippage: 100,
        oracleSeconds: ORACLE_SECONDS
      })
    );
    assertGt(_balance(WETH), amountWeth);
    assertEq(_balance(USDC), usdcBalanceBefore - amountUsdcConvert);
  }

  function test_updateFees_NoSell() public {
    _init();

    feeSplitter.updateFees(0);
    _checkBuckets(_usdcAmount(40_000), 0, _usdcAmount(60_000), 0);
    _checkBalances(address(feeSplitter), _usdcAmount(100_000), 0);

    uint256 pendingWeth = ((amountWeth * pendingShare) / 10);
    uint256 mc0BalanceWeth = ((pendingWeth * mc0Share) / 10);
    _checkBalances(masterchef0, 0, mc0BalanceWeth);
    _checkBalances(masterchef1, 0, amountWeth - mc0BalanceWeth);
  }

  function test_updateFees_PartialSell() public {
    _init();
    uint256 exchangeAmount = _usdcAmount(20_000);
    uint256 exchanged = feeSplitter.updateFees(exchangeAmount);

    uint256 pendingUsdc = (((amountUsdc * pendingShare) / 10)) - (((exchangeAmount * pendingShare) / 10));
    uint256 remainingUsdc = (((amountUsdc * (remainingShare - pendingShare)) / 10)) -
      (((exchangeAmount * (remainingShare - pendingShare)) / 10));
    _checkBuckets(pendingUsdc, 0, remainingUsdc, 0);
    _checkBalances(address(feeSplitter), amountUsdc - exchangeAmount, 0);

    uint256 exchangedPending = ((exchanged * pendingShare) / 10);
    uint256 pendingWeth = exchangedPending + ((amountWeth * pendingShare) / 10);
    uint256 mc0BalanceWeth = ((pendingWeth * mc0Share) / 10);
    _checkBalances(masterchef0, 0, mc0BalanceWeth);
    _checkBalances(masterchef1, 0, (amountWeth + exchanged) - mc0BalanceWeth);
  }

  function test_updateFees_FullSell() public {
    _init();
    uint256 exchanged = feeSplitter.updateFees(_usdcAmount(30_000));
    skip(ORACLE_SECONDS);
    exchanged += feeSplitter.updateFees(_usdcAmount(30_000));
    skip(ORACLE_SECONDS);
    exchanged += feeSplitter.updateFees(_usdcAmount(30_000));
    skip(ORACLE_SECONDS);
    exchanged += feeSplitter.updateFees(_usdcAmount(30_000));

    _checkBuckets(0, 0, 0, 0);
    _checkBalances(address(feeSplitter), 0, 0);

    uint256 exchangedPending = (exchanged / 10) * pendingShare;
    uint256 pendingWeth = (amountWeth / 10) * pendingShare + exchangedPending;
    uint256 mc0BalanceWeth = (pendingWeth / 10) * 4;
    _checkBalances(masterchef0, 0, mc0BalanceWeth);
    _checkBalances(masterchef1, 0, exchanged + amountWeth - mc0BalanceWeth);
  }

  function test_updateFees_MultipleUpdates_SingleSwapAfterAllDistributions() public {
    (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc0,
      uint256 expectedBalanceMc1,
      uint256 exchangedBalanceMc0,
      uint256 exchangedBalanceMc1
    ) = _getExpectedValuesForMultipleDistribution();

    uint256 totalExchanged;

    _distribute(50, 50, amountTokenOut[0], amountTokenIn[0]);
    _distribute(20, 80, amountTokenOut[1], amountTokenIn[1]);
    _distribute(30, 70, amountTokenOut[2], amountTokenIn[2]);
    totalExchanged = feeSplitter.updateFees(
      _tokenAmount(USDC, amountTokenOut[0] + amountTokenOut[1] + amountTokenOut[2])
    );
    assertApproxEqRel(exchangedBalanceMc0, _balance(WETH, masterchef0) - expectedBalanceMc0, 0.01 ether);
    assertApproxEqRel(exchangedBalanceMc1, _balance(WETH, masterchef1) - expectedBalanceMc1, 0.01 ether);
  }

  function test_updateFees_MultipleUpdates_PartialSwapAfterAllDistributions() public {
    (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc0,
      uint256 expectedBalanceMc1,
      uint256 exchangedBalanceMc0,
      uint256 exchangedBalanceMc1
    ) = _getExpectedValuesForMultipleDistribution();

    uint256 totalExchanged;

    _distribute(50, 50, amountTokenOut[0], amountTokenIn[0]);
    totalExchanged = feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[0]) / 4);
    _distribute(20, 80, amountTokenOut[1], amountTokenIn[1]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[1]) / 10);
    _distribute(30, 70, amountTokenOut[2], amountTokenIn[2]);
    totalExchanged += feeSplitter.updateFees(type(uint).max);
    assertApproxEqRel(exchangedBalanceMc0, _balance(WETH, masterchef0) - expectedBalanceMc0, 0.01 ether);
    assertApproxEqRel(exchangedBalanceMc1, _balance(WETH, masterchef1) - expectedBalanceMc1, 0.01 ether);
  }

  function test_updateFees_MultipleUpdates() public {
    _getExpectedValuesForMultipleDistribution();
  }

  function _getExpectedValuesForMultipleDistribution()
    internal
    returns (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc0,
      uint256 expectedBalanceMc1,
      uint256 exchangedBalanceMc0,
      uint256 exchangedBalanceMc1
    )
  {
    /*
    T0:
    Ratio P = 0.5 / R = 0.5
    Fees P = 200 / R = 200

    T1:
    Ratio P = 0.2 / R = 0.8
    Fees P = 160 / R = 640
    
    T2:
    Ratio P = 0.3 / R = 0.7
    Fees P = 150 / R = 350
    
    Final:
    Fees P = 510 / R = 1190
    Fees Mc0 = 204 = 12% / Mc1 = 1496 = 88%
    */

    uint256 totalExchanged;

    amountTokenOut = [_tokenAmount(USDC, 400), _tokenAmount(USDC, 800), _tokenAmount(USDC, 500)];
    amountTokenIn = [_tokenAmount(WETH, 4), _tokenAmount(WETH, 8), _tokenAmount(WETH, 5)];
    expectedBalanceMc0 = 2.04 ether;
    expectedBalanceMc1 = 14.96 ether;

    uint256 snapshot = vm.snapshot();
    _distribute(50, 50, amountTokenOut[0], amountTokenIn[0]);
    _distribute(20, 80, amountTokenOut[1], amountTokenIn[1]);
    _distribute(30, 70, amountTokenOut[2], amountTokenIn[2]);
    feeSplitter.updateFees(0);
    assertEq(_balance(WETH, masterchef0), expectedBalanceMc0);
    assertEq(_balance(WETH, masterchef1), expectedBalanceMc1);
    vm.revertTo(snapshot);

    snapshot = vm.snapshot();
    _distribute(50, 50, amountTokenOut[0], amountTokenIn[0]);
    totalExchanged = feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[0]));
    _distribute(20, 80, amountTokenOut[1], amountTokenIn[1]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[1]));
    _distribute(30, 70, amountTokenOut[2], amountTokenIn[2]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[2]));
    exchangedBalanceMc0 = (totalExchanged * 12) / 100;
    exchangedBalanceMc1 = (totalExchanged * 88) / 100;
    assertApproxEqRel(exchangedBalanceMc0, _balance(WETH, masterchef0) - expectedBalanceMc0, 0.01 ether);
    assertApproxEqRel(exchangedBalanceMc1, _balance(WETH, masterchef1) - expectedBalanceMc1, 0.01 ether);
    vm.revertTo(snapshot);
  }

  function _distribute(
    uint256 _pendingShare,
    uint256 _remainingShare,
    uint256 _amountTokenOut,
    uint256 _amountTokenIn
  ) internal {
    _dealTokens(_amountTokenOut, _amountTokenIn);
    feeSplitter.collectFees(_pendingShare, _remainingShare, _amountTokenOut, _amountTokenIn);
    skip(ORACLE_SECONDS);
  }

  function _dealTokens(uint256 _amountUsdc, uint256 _amountWeth) internal {
    deal(USDC, me, _amountUsdc);
    deal(WETH, me, _amountWeth);
  }

  function _checkBuckets(
    uint256 _pendingBucketTokenOut,
    uint256 _pendingBucketTokenIn,
    uint256 _remainingBucketsTokenOut,
    uint256 _remainingBucketsTokenIn
  ) internal {
    assertEq(_pendingBucketTokenOut, feeSplitter.pendingBucketTokenOut(), 'Check pending bucket token out');
    assertEq(_pendingBucketTokenIn, feeSplitter.pendingBucketTokenIn(), 'Check pending bucket token in');
    assertEq(_remainingBucketsTokenOut, feeSplitter.remainingBucketsTokenOut(), 'Check remaining bucket token out');
    assertEq(_remainingBucketsTokenIn, feeSplitter.remainingBucketsTokenIn(), 'Check remaining bucket token in');
  }

  function _checkBalances(address _target, uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    uint roundAmount = 1;
    assertEq(_amountTokenOut / roundAmount, _balance(USDC, _target) / roundAmount, 'Check balance token out');
    assertEq(_amountTokenIn / roundAmount, _balance(WETH, _target) / roundAmount, 'Check balance token in');
  }

  function _usdcAmount(uint256 _amount) internal view returns (uint256) {
    return _tokenAmount(USDC, _amount);
  }

  function _init() internal {
    _dealTokens(amountUsdc, amountWeth);
    feeSplitter.collectFees(pendingShare, remainingShare, amountUsdc, amountWeth);
    skip(ORACLE_SECONDS);
  }
}
