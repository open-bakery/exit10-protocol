// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { console } from 'forge-std/console.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10 } from '../src/Exit10.sol';
import { DepositHelper } from '../src/DepositHelper.sol';
import { IUniswapV3Router } from '../src/interfaces/IUniswapV3Router.sol';

contract DepositHelperTest is ABaseExit10Test {
  DepositHelper depositHelper;

  uint256 constant SLIPPAGE = 100;
  uint256 constant MAX_PERCENT_DELTA = 0.01 ether;

  uint256 deposit0;
  uint256 deposit1;
  uint256 unitToken1;
  uint256 token0PerToken1;
  uint256 swapAmount;

  function setUp() public override {
    super.setUp();
    unitToken1 = _tokenAmount(token1, 1);
    deposit1 = _tokenAmount(address(token1), 2);
    depositHelper = new DepositHelper(address(UNISWAP_V3_ROUTER), address(exit10), weth);
    _maxApprove(address(token0), address(token1), address(depositHelper));
    (, , token0PerToken1, ) = exit10.bootstrapLock(_addLiquidityParams(_convert1ToToken0(unitToken1 * 10), unitToken1));
    deposit0 = _ratio(deposit1);
  }

  function test_swapAndBootstrapLock_RevertIf_SwapToBigForInitialBalance() public {
    vm.expectRevert(bytes('STF'));
    depositHelper.swapAndBootstrapLock(
      deposit0,
      deposit1,
      SLIPPAGE,
      _getSwapParams(address(token0), address(token1), deposit0 * 100)
    );
  }

  function test_swapAndBootstrapLock_token0ToToken1() public {
    uint256 beforeBalance0 = _balance(address(token0));
    uint256 beforeBalance1 = _balance(address(token1));
    uint256 beforeEth = _ethBalance();

    (uint256 expectedLiquidity, uint256 expectedAdded0, uint256 expectedAdded1) = _bootstrapLockVanilla(); // vanilla bootstrap lock to compare with

    uint256 beforeLiquidity = _getLiquidity();
    uint256 beforeBoot = _balance(boot);
    uint256 amount1 = expectedAdded1 / 2;
    uint256 swapAmount0 = _convert1ToToken0(amount1);

    (, uint128 addedLiquidity, uint256 added0, uint256 added1) = depositHelper.swapAndBootstrapLock(
      expectedAdded0 + swapAmount0,
      expectedAdded1 - amount1,
      SLIPPAGE,
      _getSwapParams(address(token0), address(token1), swapAmount0)
    );

    assertApproxEqRel(added0, expectedAdded0, MAX_PERCENT_DELTA, 'Expected added0');
    assertApproxEqRel(added1, expectedAdded1, MAX_PERCENT_DELTA, 'Expected added1');
    assertApproxEqRel(addedLiquidity, expectedLiquidity, MAX_PERCENT_DELTA, 'Expected liquidity');

    assertEq(_getLiquidity(), beforeLiquidity + addedLiquidity, 'Check liquidity');
    assertEq(_balance(boot), beforeBoot + addedLiquidity * exit10.TOKEN_MULTIPLIER(), 'BOOT minted');
    assertEq(_ethBalance(), beforeEth, 'ETH balance same');
    assertLt(_balance(address(token0)), beforeBalance0, 'balance0 less');
    assertLt(_balance(address(token1)), beforeBalance1, 'balance1 less');

    _checkBalances(address(depositHelper), address(token0), address(token1), 0, 0);
    _checkBuckets(0, 0, 0, beforeLiquidity + addedLiquidity);
  }

  function test_swapAndBootstrapLock_token0Token1_ZeroSwap() public {
    (uint256 expectedLiquidity, uint256 expectedAdded0, uint256 expectedAdded1) = _bootstrapLockVanilla();

    (, uint128 addedLiquidity, uint256 added0, uint256 added1) = depositHelper.swapAndBootstrapLock(
      expectedAdded0,
      expectedAdded1,
      SLIPPAGE,
      _getSwapParams(usdc, weth, 0)
    );

    assertEq(added0, expectedAdded0, 'Expected added0');
    assertEq(added1, expectedAdded1, 'Expected added1');
    assertEq(addedLiquidity, expectedLiquidity, 'Expected liquidity');
  }

  function test_swapAndBootstrapLock_token1ToToken0() public {
    uint256 beforeBalance0 = _balance(address(token0));
    uint256 beforeBalance1 = _balance(address(token1));

    (uint256 expectedLiquidity, uint256 expectedAdded0, uint256 expectedAdded1) = _bootstrapLockVanilla();

    uint256 amount0 = expectedAdded0 / 2;
    uint256 swapAmount1 = _convert0ToToken1(amount0);
    uint256 beforeLiquidity = _getLiquidity();
    uint256 beforeBoot = _balance(boot);

    (, uint128 addedLiquidity, uint256 added0, uint256 added1) = depositHelper.swapAndBootstrapLock(
      expectedAdded0 - amount0,
      expectedAdded1 + swapAmount1,
      SLIPPAGE,
      _getSwapParams(address(token1), address(token0), swapAmount1)
    );

    assertApproxEqRel(added0, expectedAdded0, MAX_PERCENT_DELTA, 'Expected added0');
    assertApproxEqRel(added1, expectedAdded1, MAX_PERCENT_DELTA, 'Expected added1');
    assertApproxEqRel(addedLiquidity, expectedLiquidity, MAX_PERCENT_DELTA, 'Expected liquidity');

    assertEq(_getLiquidity(), beforeLiquidity + addedLiquidity, 'Check liquidity');
    assertEq(_balance(boot), beforeBoot + addedLiquidity * exit10.TOKEN_MULTIPLIER(), 'BOOT minted');
    assertLt(_balance(address(token0)), beforeBalance0, 'balance0 less');
    assertLt(_balance(address(token1)), beforeBalance1, 'balance1 less');

    _checkBalances(address(depositHelper), address(token0), address(token1), 0, 0);
    _checkBuckets(0, 0, 0, beforeLiquidity + addedLiquidity);
  }

  // // note: not repeating all tests, assuming the _swap part works the same
  function test_swapAndCreateBond() public {
    uint256 beforeBalance0 = _balance(address(token0));
    uint256 beforeBalance1 = _balance(address(token1));
    uint256 beforeEth = _ethBalance();
    (, , , uint256 stateBootstrapBefore) = exit10.getBuckets();

    _skipBootstrap();
    (uint256 expectedLiquidity, uint256 expectedAdded0, uint256 expectedAdded1) = _createBondVanilla(); // vanilla bootstrap lock to compare with
    uint256 amount1 = expectedAdded1 / 2;
    uint256 swapAmount0 = _convert1ToToken0(amount1);

    uint256 beforeLiquidity = _getLiquidity();

    (uint256 bondId, uint128 addedLiquidity, uint256 added0, uint256 added1) = depositHelper.swapAndCreateBond(
      expectedAdded0 + swapAmount0,
      expectedAdded1 - amount1,
      SLIPPAGE,
      _getSwapParams(address(token0), address(token1), swapAmount0)
    );

    assertApproxEqRel(added0, expectedAdded0, MAX_PERCENT_DELTA, 'Expected added0');
    assertApproxEqRel(added1, expectedAdded1, MAX_PERCENT_DELTA, 'Expected added1');
    assertApproxEqRel(addedLiquidity, expectedLiquidity, MAX_PERCENT_DELTA, 'Expected liquidity');

    assertEq(_getLiquidity(), beforeLiquidity + addedLiquidity, 'Check liquidity');
    assertEq(IERC721(exit10.NFT()).balanceOf(address(this)), 1, 'NFT balance'); // first minted in _createBondVanilla
    assertEq(_ethBalance(), beforeEth, 'ETH balance same');
    assertLt(_balance(address(token0)), beforeBalance0, 'balance0 less');
    assertLt(_balance(address(token1)), beforeBalance1, 'balance1 less');

    _checkBalances(address(depositHelper), address(token0), address(token1), 0, 0);
    // liquidityBefore includes what was added to bootstarpBasket in setUp
    _checkBuckets(beforeLiquidity - stateBootstrapBefore + addedLiquidity, 0, 0, stateBootstrapBefore);
    _checkBondData(bondId, addedLiquidity, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
  }

  function test_frontrunDepositHelperUnit_Revert() public {
    // change default parms
    deposit1 = _tokenAmount(address(token1), 100_000);
    deposit0 = _ratio(deposit1);
    uint256 soldEther = 1000 ether;

    (, uint256 expectedAdded0, uint256 expectedAdded1) = _bootstrapLockVanilla();

    // prepare front runner
    _mintAndApprove(alice, weth, soldEther, address(UNISWAP_V3_ROUTER));
    _maxApproveFrom(alice, usdc, address(UNISWAP_V3_ROUTER));
    uint256 wethBalanceBefore = _balance(weth, alice);

    uint256 amount0 = _tokenAmount(usdc, 10); // is relative small such that profit is not too high
    uint256 swapAmount1 = _convert0ToToken1(amount0);

    uint256 snapshot = vm.snapshot();
    uint256 amountOutMinimum = _swap(address(token1), address(token0), swapAmount1);
    vm.revertTo(snapshot); // restores the state

    IUniswapV3Router.ExactInputSingleParams memory slippageParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: address(token1),
      tokenOut: address(token0),
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: swapAmount1,
      amountOutMinimum: amountOutMinimum,
      sqrtPriceLimitX96: 0
    });

    (, uint128 noFrontRunLiquidity, , ) = depositHelper.swapAndBootstrapLock(
      expectedAdded0 - amount0,
      expectedAdded1 + swapAmount1,
      SLIPPAGE,
      slippageParams
    );

    vm.revertTo(snapshot); // restores the state

    // frontrunning the trade in the opposite direction will not succeed

    //frontrun lp
    vm.prank(alice);
    uint256 receivedUsdc = UNISWAP_V3_ROUTER.exactInputSingle(
      IUniswapV3Router.ExactInputSingleParams({
        tokenIn: weth,
        tokenOut: usdc,
        fee: 500,
        recipient: alice,
        deadline: block.timestamp,
        amountIn: soldEther,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );

    // provide liquidity
    vm.expectRevert(bytes('Too little received'));
    (, uint256 frontRunLiquidity, , ) = depositHelper.swapAndBootstrapLock(
      expectedAdded0 - amount0,
      expectedAdded1 + swapAmount1,
      SLIPPAGE,
      slippageParams
    );

    // // backrun lp
    vm.prank(alice);
    UNISWAP_V3_ROUTER.exactInputSingle(
      IUniswapV3Router.ExactInputSingleParams({
        tokenIn: usdc,
        tokenOut: weth,
        fee: 500,
        recipient: alice,
        deadline: block.timestamp,
        amountIn: receivedUsdc,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );

    // // Frontrunnig will not harm the lp
    assertGt(noFrontRunLiquidity, frontRunLiquidity, 'noFrontRunLiquidity > frontRunLiquidity');
    assertEq(frontRunLiquidity, 0, 'frontRunLiquidity == 0');

    // // Frontrunner will not benefit
    assertLt(_balance(weth, alice), wethBalanceBefore, 'frontRunnerAfterBalanceWeth < frontRunnerBeforeBalanceWeth');
  }

  function test_frontrunProtectionSuceedsWithToken0ToToken1Frontrun() public {
    // setup
    uint256 flashLoan = _tokenAmount(address(token0), 1_000_0000);
    _mintAndApprove(alice, address(token0), flashLoan, address(UNISWAP_V3_ROUTER));
    _maxApproveFrom(alice, address(token1), address(UNISWAP_V3_ROUTER));

    (
      ,
      uint256 swapAmount0,
      IUniswapV3Router.ExactInputSingleParams memory swapParams
    ) = _provideLiquidityWithToken0ToToken1();

    // FRONTRUN
    vm.prank(alice);
    UNISWAP_V3_ROUTER.exactInputSingle(_getSwapParamsFrom(address(token0), address(token1), flashLoan, alice));

    // PROVIDE LIQUIDITY W/ FRONTRUN PROTECTION REVERTS
    uint256 amount1 = _convert0ToToken1(swapAmount0);
    vm.expectRevert(bytes('SPL')); // Square root price limit (see:   // https://docs.uniswap.org/contracts/v3/reference/error-codes)
    depositHelper.swapAndBootstrapLock(deposit0 + swapAmount0, deposit1 - amount1, SLIPPAGE, swapParams);
  }

  function test_frontrunProtectionRevertsWithToken1ToToken0Frontrun() public {
    // prepare
    uint256 flashLoanStart = _tokenAmount(weth, 1_000_000);
    _maxApproveFrom(alice, address(token0), address(UNISWAP_V3_ROUTER));
    _mintAndApprove(alice, address(token1), flashLoanStart, address(UNISWAP_V3_ROUTER));
    uint256 attackerBeforeBalance1 = _balance(address(token1), alice);

    (
      uint256 expectedLiquidity,
      uint256 swapAmount0,
      IUniswapV3Router.ExactInputSingleParams memory swapParams
    ) = _provideLiquidityWithToken0ToToken1();

    // FRONTRUN
    vm.prank(alice);
    uint256 flashLoanEnd = UNISWAP_V3_ROUTER.exactInputSingle(
      _getSwapParamsFrom(address(token1), address(token0), flashLoanStart, alice)
    );

    // PROVIDE LIQUIDITY W/ FRONTRUN PROTECTION DOES REVERT
    uint256 amount1 = _convert0ToToken1(swapAmount0);
    vm.expectRevert(bytes('Price slippage check'));
    (, uint128 realizedLiquidity, , ) = depositHelper.swapAndBootstrapLock(
      deposit0 + swapAmount0,
      deposit1 - amount1,
      SLIPPAGE,
      swapParams
    );

    // BACKRUN
    vm.prank(alice);
    UNISWAP_V3_ROUTER.exactInputSingle(_getSwapParamsFrom(usdc, weth, flashLoanEnd, alice));

    // CHECKS
    assertLt(realizedLiquidity, expectedLiquidity, 'LP tokens minted did not increase');
    assertGe(attackerBeforeBalance1, _balance(address(token1), alice), 'Attacker balance descreased');
  }

  function _returnPriceInUint() internal view returns (uint256) {
    (uint160 sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    uint256 a = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 10 ** token0.decimals();
    uint256 b = 1 << 192;
    return a / b;
  }

  function _returnPriceInUSD(uint160 _sqrtPriceX96) internal pure returns (uint256) {
    uint256 a = uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96) * USDC_DECIMALS;
    uint256 b = 1 << 192;
    uint256 uintPrice = a / b;
    return (1 ether * 1e6) / uintPrice;
  }

  function _convert0ToToken1(uint256 _amount0) internal view returns (uint256 _amount0ConvertedToToken1) {
    uint256 price = _returnPriceInUint();
    _amount0ConvertedToToken1 = (_amount0 * price) / 10 ** token0.decimals();
  }

  function _convert1ToToken0(uint256 _amount1) internal view returns (uint256 _amount1ConvertedToToken0) {
    uint256 price = _returnPriceInUint();
    if (price == 0) return 0;
    _amount1ConvertedToToken0 = (_amount1 * 10 ** token0.decimals()) / price;
  }

  function _ratio(uint256 _amount1) internal view returns (uint256 _amount0) {
    _amount0 = (_amount1 * token0PerToken1) / 10 ** token1.decimals();
  }

  function _bootstrapLockVanilla()
    internal
    returns (uint256 _expectedAddedLiquidity, uint256 _expectedAdded0, uint256 _expectedAdded1)
  {
    uint256 snapshot = vm.snapshot();

    (, _expectedAddedLiquidity, _expectedAdded0, _expectedAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(deposit0, deposit1)
    );

    assertGt(_expectedAddedLiquidity, 0, 'Added liquidity');

    vm.revertTo(snapshot); // restores the state
  }

  function _createBondVanilla()
    internal
    returns (uint256 _expectedAddedLiquidity, uint256 _expectedAdded0, uint256 _expectedAdded1)
  {
    uint256 snapshot = vm.snapshot();

    (, _expectedAddedLiquidity, _expectedAdded0, _expectedAdded1) = exit10.createBond(
      _addLiquidityParams(deposit0, deposit1)
    );

    assertGt(_expectedAddedLiquidity, 0, 'Added liquidity');

    vm.revertTo(snapshot); // restores the state
  }

  function _getSwapParams(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) internal view returns (IUniswapV3Router.ExactInputSingleParams memory) {
    return
      IUniswapV3Router.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: 500,
        recipient: address(depositHelper),
        deadline: block.timestamp,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });
  }

  function _getSwapParamsFrom(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    address _beneficiary
  ) internal view returns (IUniswapV3Router.ExactInputSingleParams memory swapParamsFrom) {
    return
      IUniswapV3Router.ExactInputSingleParams({
        tokenIn: _tokenIn,
        tokenOut: _tokenOut,
        fee: 500,
        recipient: _beneficiary,
        deadline: block.timestamp,
        amountIn: _amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });
  }

  function _provideLiquidityWithToken0ToToken1()
    internal
    returns (
      uint256 _expectedLiquidity,
      uint256 _swapAmount0,
      IUniswapV3Router.ExactInputSingleParams memory _swapParams
    )
  {
    // change default parms
    deposit1 = _tokenAmount(weth, 100_000);
    deposit0 = _ratio(deposit1);
    _swapAmount0 = _tokenAmount(address(token0), 10); // is relative small such that profit is not too high

    (, uint256 expectedAdded0, uint256 expectedAdded1) = _bootstrapLockVanilla(); // vanilla bootstrap lock to compare with
    uint256 amount1 = _convert0ToToken1(_swapAmount0);

    uint256 snapshot = vm.snapshot();

    // min amount TODO: use min amount
    uint256 amountOutMinimum = _swap(address(token0), address(token1), _swapAmount0);
    vm.revertTo(snapshot); // restores the state

    /*
      WE TRADE USDC FOR WETH AND WANT TO PROTECT US FROM THE PRICE OF WETH GOING UP.
      AS the price is defined as weth/usdc, we want to protect us from the price going down.

    */

    (uint160 sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    uint160 sqrtPriceLimitX96 = sqrtPriceX96 - (sqrtPriceX96 / 1000);

    _swapParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: address(token0),
      tokenOut: address(token1),
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: _swapAmount0,
      amountOutMinimum: amountOutMinimum,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    // min lp amounts
    (, _expectedLiquidity, , ) = depositHelper.swapAndBootstrapLock(
      expectedAdded0 + _swapAmount0,
      expectedAdded1 - amount1,
      SLIPPAGE,
      _swapParams
    );
    vm.revertTo(snapshot); // restores the state

    return (_expectedLiquidity, _swapAmount0, _swapParams);
  }
}
