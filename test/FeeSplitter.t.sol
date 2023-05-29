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
  address masterchef;
  address exit10;

  uint32 constant ORACLE_SECONDS = 60;

  uint256 mc0Share = 4;
  uint256 pendingShare = 4;
  uint256 remainingShare = 6 + pendingShare;
  uint256 amountUsdc = _usdcAmount(100_000);
  uint256 amountWeth = 10_000 ether;

  function setUp() public {
    Masterchef mc0 = new Masterchef(WETH, 2 weeks);
    masterchef = address(mc0);

    feeSplitter = new FeeSplitter(masterchef, swapper);
    feeSplitter.setExit10(me); // = address(this)
    exit10 = feeSplitter.exit10();

    mc0.add(10, address(0x01));
    mc0.transferOwnership(address(feeSplitter));
    _maxApprove(USDC, WETH, address(feeSplitter));
  }

  function test_collectFees_RevertIf_NotAuthorized() public {
    vm.expectRevert(bytes('FeeSplitter: Caller not authorized'));
    vm.prank(bob);
    feeSplitter.collectFees(amountUsdc, amountWeth);
  }

  function test_collectFees() public {
    _dealTokens(amountUsdc, amountWeth);
    // note: using shares instead of values because in FeeSplitter.collectFees, only the ratio is used.
    feeSplitter.collectFees(amountUsdc, amountWeth);
    _checkBalances(address(feeSplitter), amountUsdc, amountWeth);
  }

  function test_collectFees_ZeroTokens() public {
    _dealTokens(amountUsdc, amountWeth);
    feeSplitter.collectFees(0, 0);
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
    _checkBalances(address(feeSplitter), _usdcAmount(100_000), 0);

    uint256 mc = ((amountWeth * 2) / 10);
    uint256 balanceExit10 = amountWeth - mc;
    _checkBalances(masterchef, 0, mc);
    _checkBalances(exit10, 0, balanceExit10);
  }

  function test_updateFees_PartialSell() public {
    _init();
    uint256 exchangeAmount = _usdcAmount(20_000);
    uint256 exchanged = feeSplitter.updateFees(exchangeAmount);

    uint256 totalWeth = amountWeth + exchanged;
    uint256 mc = ((totalWeth * 2) / 10);
    uint256 balanceExit10 = totalWeth - mc;

    _checkBalances(address(feeSplitter), amountUsdc - exchangeAmount, 0);
    _checkBalances(masterchef, 0, mc);
    _checkBalances(exit10, 0, balanceExit10);
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

    uint256 totalWeth = amountWeth + exchanged;
    uint256 mc = ((totalWeth * 2) / 10);
    uint256 balanceExit10 = totalWeth - mc;

    _checkBalances(address(feeSplitter), 0, 0);
    _checkBalances(masterchef, 0, mc);
    _checkBalances(exit10, 0, balanceExit10);
  }

  function test_updateFees_MultipleUpdates_SingleSwapAfterAllDistributions() public {
    (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc,
      uint256 expectedBalanceExit10,
      uint256 exchangedBalanceMc,
      uint256 exchangedBalanceExit10
    ) = _getExpectedValuesForMultipleDistribution();

    uint256 totalExchanged;

    _distribute(amountTokenOut[0], amountTokenIn[0]);
    _distribute(amountTokenOut[1], amountTokenIn[1]);
    _distribute(amountTokenOut[2], amountTokenIn[2]);
    totalExchanged = feeSplitter.updateFees(
      _tokenAmount(USDC, amountTokenOut[0] + amountTokenOut[1] + amountTokenOut[2])
    );
    assertApproxEqRel(exchangedBalanceMc, _balance(WETH, masterchef) - expectedBalanceMc, 0.01 ether);
    assertApproxEqRel(exchangedBalanceExit10, _balance(WETH, exit10) - expectedBalanceExit10, 0.01 ether);
  }

  function test_updateFees_MultipleUpdates_PartialSwapAfterAllDistributions() public {
    (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc,
      uint256 expectedBalanceExit10,
      uint256 exchangedBalanceMc,
      uint256 exchangedBalanceExit10
    ) = _getExpectedValuesForMultipleDistribution();

    uint256 totalExchanged;

    _distribute(amountTokenOut[0], amountTokenIn[0]);
    totalExchanged = feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[0]) / 4);
    _distribute(amountTokenOut[1], amountTokenIn[1]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[1]) / 10);
    _distribute(amountTokenOut[2], amountTokenIn[2]);
    totalExchanged += feeSplitter.updateFees(type(uint).max);
    assertApproxEqRel(exchangedBalanceMc, _balance(WETH, masterchef) - expectedBalanceMc, 0.01 ether);
    assertApproxEqRel(exchangedBalanceExit10, _balance(WETH, exit10) - expectedBalanceExit10, 0.01 ether);
  }

  function test_updateFees_MultipleUpdates() public {
    _getExpectedValuesForMultipleDistribution();
  }

  function _getExpectedValuesForMultipleDistribution()
    internal
    returns (
      uint256[3] memory amountTokenOut,
      uint256[3] memory amountTokenIn,
      uint256 expectedBalanceMc,
      uint256 expectedBalanceExit10,
      uint256 exchangedBalanceMc,
      uint256 exchangedBalanceExit10
    )
  {
    /*
    Total ETH = 17
    Total USDC = 1700

    Expected mc = 3.4
    Expected Exit10 = 13.6
    */

    uint256 totalExchanged;

    amountTokenOut = [_tokenAmount(USDC, 400), _tokenAmount(USDC, 800), _tokenAmount(USDC, 500)];
    amountTokenIn = [_tokenAmount(WETH, 4), _tokenAmount(WETH, 8), _tokenAmount(WETH, 5)];
    expectedBalanceMc = 3.4 ether;
    expectedBalanceExit10 = 13.6 ether;

    uint256 snapshot = vm.snapshot();
    _distribute(amountTokenOut[0], amountTokenIn[0]);
    _distribute(amountTokenOut[1], amountTokenIn[1]);
    _distribute(amountTokenOut[2], amountTokenIn[2]);
    feeSplitter.updateFees(0);
    assertEq(_balance(WETH, masterchef), expectedBalanceMc, 'Snapshot balance mc check');
    assertEq(_balance(WETH, exit10), expectedBalanceExit10, 'Snapshot balance exit10 check');
    vm.revertTo(snapshot);

    snapshot = vm.snapshot();
    _distribute(amountTokenOut[0], amountTokenIn[0]);
    totalExchanged = feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[0]));
    _distribute(amountTokenOut[1], amountTokenIn[1]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[1]));
    _distribute(amountTokenOut[2], amountTokenIn[2]);
    totalExchanged += feeSplitter.updateFees(_tokenAmount(USDC, amountTokenOut[2]));
    exchangedBalanceMc = (totalExchanged * 20) / 100;
    exchangedBalanceExit10 = totalExchanged - exchangedBalanceMc;
    assertApproxEqRel(
      exchangedBalanceMc,
      _balance(WETH, masterchef) - expectedBalanceMc,
      0.01 ether,
      'Snapshot exchanged balance mc check'
    );
    assertApproxEqRel(
      exchangedBalanceExit10,
      _balance(WETH, exit10) - expectedBalanceExit10,
      0.01 ether,
      'Snapshot exchanged balance exit10 check'
    );
    vm.revertTo(snapshot);
  }

  function _distribute(uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    _dealTokens(_amountTokenOut, _amountTokenIn);
    feeSplitter.collectFees(_amountTokenOut, _amountTokenIn);
    skip(ORACLE_SECONDS);
  }

  function _dealTokens(uint256 _amountUsdc, uint256 _amountWeth) internal {
    deal(USDC, me, _balance(USDC, exit10) + _amountUsdc);
    deal(WETH, me, _balance(WETH, exit10) + _amountWeth);
  }

  function _checkBalances(address _target, uint256 _amountTokenOut, uint256 _amountTokenIn) internal {
    uint256 diff = 1;
    assertApproxEqAbs(_amountTokenOut, _balance(USDC, _target), diff, 'Check balance token out');
    assertApproxEqAbs(_amountTokenIn, _balance(WETH, _target), diff, 'Check balance token in');
  }

  function _usdcAmount(uint256 _amount) internal view returns (uint256) {
    return _tokenAmount(USDC, _amount);
  }

  function _init() internal {
    _dealTokens(amountUsdc, amountWeth);
    feeSplitter.collectFees(amountUsdc, amountWeth);
    skip(ORACLE_SECONDS);
  }
}
