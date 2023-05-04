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

  uint256 depositWeth = _tokenAmount(weth, 2);
  uint256 depositUsdc;
  uint256 swapAmount = _tokenAmount(usdc, 1000);
  uint256 etherAmount = 1 ether;

  uint256 usdcPerWeth;

  uint256 liquidityAddedVanilla;
  uint256 addedUsdcVanilla;
  uint256 addedWethVanilla;

  function setUp() public override {
    super.setUp();
    depositHelper = new DepositHelper(address(UNISWAP_V3_ROUTER), address(exit10), weth);
    _maxApprove(weth, usdc, address(depositHelper));

    // adding very high usdc gives me the pool ratio
    (, , usdcPerWeth, ) = exit10.bootstrapLock(_addLiquidityParams(_balance(usdc), _tokenAmount(weth, 1)));
    depositUsdc = _ratio(depositWeth);
  }

  function test_swapAndBootstrapLock_RevertIf_SwapToBigForInitialBalance() public {
    vm.expectRevert(bytes('STF'));
    depositHelper.swapAndBootstrapLock(depositUsdc, depositWeth, _getSwapParams(usdc, weth, swapAmount * 100));
  }

  function test_swapAndBootstrapLock_UsdcToWeth_SwapIncreasesDeposit() public {
    uint256 usdcBalanceBefore = _balance(usdc);
    uint256 wethBalanceBefore = _balance(usdc);
    uint256 ethBalanceBefore = _ethBalance();

    _bootstrapLockVanilla(); // vanilla bootstrap lock to compare with

    uint256 liquidityBefore = _getLiquidity();
    uint256 bootBefore = _balance(boot);

    (, uint128 liquidityAdded, uint256 addedUsdc, uint256 addedWeth) = depositHelper.swapAndBootstrapLock(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      _getSwapParams(usdc, weth, swapAmount)
    );

    assertEq(addedUsdc, addedUsdcVanilla + swapAmount, 'Added vanilla USDC + swap amount');
    assertGt(addedWeth, addedWethVanilla, 'Added more WETH than vanilla');
    assertGt(liquidityAdded, liquidityAddedVanilla, 'Added more liquidity than vanilla');

    assertEq(_getLiquidity(), liquidityBefore + liquidityAdded, 'Liquidity added');
    assertEq(_balance(boot), bootBefore + liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'BOOT minted');
    assertEq(_ethBalance(), ethBalanceBefore, 'ETH balance same');
    assertLt(_balance(weth), wethBalanceBefore, 'WETH balance less');
    assertLt(_balance(usdc), usdcBalanceBefore, 'USDC balanbce less');

    _checkBalances(address(depositHelper), usdc, weth, 0, 0);
    _checkBuckets(0, 0, 0, liquidityBefore + liquidityAdded);
  }

  function test_swapAndBootstrapLock_UsdcToWeth_SwapReducesDeposit() public {
    _bootstrapLockVanilla();

    (, uint128 liquidityAdded, uint256 addedUsdc, uint256 addedWeth) = depositHelper.swapAndBootstrapLock(
      depositUsdc,
      depositWeth,
      _getSwapParams(usdc, weth, swapAmount)
    );

    assertEq(addedUsdc, addedUsdcVanilla - swapAmount, 'Added vanilla USDC - swap amount');
    // added even less weth because price changed with the swap
    assertLt(addedWeth, addedWethVanilla - (swapAmount * 1e18) / usdcPerWeth, 'Added vanilla WETH - swap amount');
    assertLt(liquidityAdded, liquidityAddedVanilla, 'Added less liquidity than vanilla');
  }

  function test_swapAndBootstrapLock_UsdcToWeth_ZeroSwap() public {
    _bootstrapLockVanilla();

    (, uint128 liquidityAdded, uint256 addedUsdc, uint256 addedWeth) = depositHelper.swapAndBootstrapLock(
      depositUsdc,
      depositWeth,
      _getSwapParams(usdc, weth, 0)
    );

    assertEq(addedUsdc, addedUsdcVanilla, 'Added USDC same as vanilla');
    assertEq(addedWeth, addedWethVanilla, 'Added WETH same as vanilla');
    assertEq(liquidityAdded, liquidityAddedVanilla, 'Added same liquidity as vanilla');
  }

  function test_swapAndBootstrapLock_UsdcToWethWithEthValue() public {
    uint256 ethBalanceBefore = _ethBalance();
    uint256 wethBalanceBefore = _balance(weth);

    (, , , uint256 addedWeth) = depositHelper.swapAndBootstrapLock{ value: etherAmount }(
      depositUsdc * 100,
      depositWeth,
      _getSwapParams(usdc, weth, swapAmount)
    );

    assertGt(addedWeth, depositWeth + etherAmount, 'WETH_ETH added more than put in');
    // ether sent as value was all converted to weth, all eth + weth was used.
    assertEq(_ethBalance(), ethBalanceBefore - etherAmount, 'ETH balance decrease');
    // rough eq because of weth from the swap is imprecise
    _assertEqRoughly(_balance(weth), wethBalanceBefore - depositWeth, 'WETH balance decrease');
  }

  function test_swapAndBootstrapLock_WethToUsdc() public {
    uint256 swapAmountWeth = _tokenAmount(weth, 1);
    uint256 usdcBalanceBefore = _balance(usdc);
    uint256 wethBalanceBefore = _balance(usdc);

    _bootstrapLockVanilla();

    uint256 liquidityBefore = _getLiquidity();
    uint256 bootBefore = _balance(boot);

    (, uint128 liquidityAdded, uint256 addedUsdc, uint256 addedWeth) = depositHelper.swapAndBootstrapLock(
      depositUsdc * 2,
      depositWeth + swapAmountWeth * 2,
      _getSwapParams(weth, usdc, swapAmountWeth)
    );

    _assertEqRoughly(addedWeth, addedWethVanilla + swapAmountWeth, 'Added vanilla WETH + swap amount');
    assertGt(addedUsdc, addedUsdcVanilla, 'Added more USDC than vanilla');
    assertGt(liquidityAdded, liquidityAddedVanilla, 'Added more liquidity than vanilla');
    assertEq(_getLiquidity(), liquidityBefore + liquidityAdded, 'Liquidity added');
    assertEq(_balance(boot), bootBefore + liquidityAdded * exit10.TOKEN_MULTIPLIER(), 'BOOT minted');
    assertLt(_balance(weth), wethBalanceBefore, 'WETH balance less');
    assertLt(_balance(usdc), usdcBalanceBefore, 'USDC balanbce less');

    _checkBalances(address(depositHelper), usdc, weth, 0, 0);
    _checkBuckets(0, 0, 0, liquidityBefore + liquidityAdded);
  }

  // note: not repeating all tests, assuming the _swap part works the same
  function test_swapAndCreateBond() public {
    uint256 usdcBalanceBefore = _balance(usdc);
    uint256 wethBalanceBefore = _balance(usdc);
    uint256 ethBalanceBefore = _ethBalance();
    (, , , uint256 stateBootstrapBefore) = exit10.getBuckets();

    _skipBootstrap();
    _createBondVanilla(); // vanilla bootstrap lock to compare with

    uint256 liquidityBefore = _getLiquidity();

    (uint256 bondId, uint128 liquidityAdded, uint256 addedUsdc, uint256 addedWeth) = depositHelper.swapAndCreateBond(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      _getSwapParams(usdc, weth, swapAmount)
    );

    assertEq(addedUsdc, addedUsdcVanilla + swapAmount, 'Added vanilla USDC + swap amount');
    assertGt(addedWeth, addedWethVanilla, 'Added more WETH than vanilla');
    assertGt(liquidityAdded, liquidityAddedVanilla, 'Added more liquidity than vanilla');

    assertEq(_getLiquidity(), liquidityBefore + liquidityAdded, 'Liquidity added');
    assertEq(IERC721(exit10.NFT()).balanceOf(address(this)), 2, 'NFT balance'); // first minted in _createBondVanilla
    assertEq(_ethBalance(), ethBalanceBefore, 'ETH balance same');
    assertLt(_balance(weth), wethBalanceBefore, 'WETH balance less');
    assertLt(_balance(usdc), usdcBalanceBefore, 'USDC balanbce less');

    _checkBalances(address(depositHelper), usdc, weth, 0, 0);
    // liquidityBefore includes what was added to bootstarpBasket in setUp
    _checkBuckets(liquidityBefore - stateBootstrapBefore + liquidityAdded, 0, 0, stateBootstrapBefore);
    _checkBondData(bondId, liquidityAdded, 0, block.timestamp, 0, uint8(Exit10.BondStatus.active));
  }

  function test_frontrunDepositHelperUnit() public {
    _bootstrapLockVanilla(); // vanilla bootstrap lock to compare with

    // change default parms
    depositWeth = _tokenAmount(weth, 100_000);
    depositUsdc = _ratio(depositWeth);
    swapAmount = _tokenAmount(usdc, 10); // is relative small such that profit is not too high
    uint256 soldEther = 0.1 ether;

    // prepare front runner
    _mintAndApprove(alice, weth, soldEther, address(UNISWAP_V3_ROUTER));
    _maxApproveFrom(alice, usdc, address(UNISWAP_V3_ROUTER));
    uint256 wethBalanceBefore = _balance(weth, alice);

    uint256 snapshot = vm.snapshot();

    // min amount
    uint256 amountOutMinimum = _swap(weth, usdc, swapAmount);

    vm.revertTo(snapshot); // restores the state

    IUniswapV3Router.ExactInputSingleParams memory slippageParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: weth,
      tokenOut: usdc,
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: swapAmount,
      amountOutMinimum: amountOutMinimum,
      sqrtPriceLimitX96: 0
    });

    // min lp amounts
    (, uint128 eliquidityAdded, , ) = depositHelper.swapAndBootstrapLock(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      slippageParams
    );

    vm.revertTo(snapshot); // restores the state

    // frontrunning the trade in the opposite direction will succeed

    // frontrun lp
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
    (, uint128 eLiquidityRealized, , ) = depositHelper.swapAndBootstrapLock(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      slippageParams
    );

    // backrun lp
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

    // Frontrunnig will harm the lp
    assertLt(eLiquidityRealized, eliquidityAdded, 'eLiquidityRealized < eliquidityAdded');

    // While benefiting the frontrunner
    assertGe(_balance(weth, alice), wethBalanceBefore, 'wethBalanceAfterAlice < wethBalanceBeforeAlice');
  }

  function test_frontrunDepositHelperUnitFailed() public {
    _bootstrapLockVanilla(); // vanilla bootstrap lock to compare with

    // change default parms
    depositWeth = _tokenAmount(weth, 100_000);
    depositUsdc = _ratio(depositWeth);
    swapAmount = _tokenAmount(usdc, 10); // is relative small such that profit is not too high
    uint256 soldEther = 0.1 ether;

    // prepare front runner
    _mintAndApprove(alice, weth, soldEther, address(UNISWAP_V3_ROUTER));
    _maxApproveFrom(alice, usdc, address(UNISWAP_V3_ROUTER));
    uint256 wethBalanceBefore = _balance(weth, alice);

    uint256 snapshot = vm.snapshot();

    // min amount
    uint256 amountOutMinimum = _swap(weth, usdc, swapAmount);
    (uint160 sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    uint160 sqrtPriceLimitX96 = sqrtPriceX96 + (sqrtPriceX96 / 1000);
    // console.log('sqrtPriceX96: ', _returnPriceInUSD(sqrtPriceX96));
    // console.log('sqrtPriceLimitX96: ', _returnPriceInUSD(sqrtPriceLimitX96));

    vm.revertTo(snapshot); // restores the state

    IUniswapV3Router.ExactInputSingleParams memory slippageParams = IUniswapV3Router.ExactInputSingleParams({
      tokenIn: weth,
      tokenOut: usdc,
      fee: 500,
      recipient: address(depositHelper),
      deadline: block.timestamp,
      amountIn: swapAmount,
      amountOutMinimum: amountOutMinimum,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    // console.log('Price in USD: ', _returnPriceInUSD());

    // min lp amounts
    (, uint128 eliquidityAdded, , ) = depositHelper.swapAndBootstrapLock(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      slippageParams
    );

    // console.log('Price in USD After Trade: ', _returnPriceInUSD());
    vm.revertTo(snapshot); // restores the state

    // frontrunning the trade in the opposite direction will succeed

    // frontrun lp
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

    // console.log('Price in USD after frontrun: ', _returnPriceInUSD());

    // provide liquidity
    (, uint128 eLiquidityRealized, , ) = depositHelper.swapAndBootstrapLock(
      depositUsdc + swapAmount * 2,
      depositWeth * 2,
      slippageParams
    );

    // backrun lp
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

    // Frontrunnig will harm the lp
    assertLt(eLiquidityRealized, eliquidityAdded, 'eLiquidityRealized < eliquidityAdded');

    // While benefiting the frontrunner
    assertGe(_balance(weth, alice), wethBalanceBefore, 'wethBalanceAfterAlice < wethBalanceBeforeAlice');

    // console.log('wethBalanceBefore: ', wethBalanceBefore);
    // console.log('wethBalanceAfter: ', _balance(weth, alice));

    // console.log('eLiquidityRealized: ', eLiquidityRealized);
    // console.log('eliquidityAdded: ', eliquidityAdded);
  }

  function _returnPriceInUSD(uint160 sqrtPriceX96) internal pure returns (uint256) {
    uint256 a = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * USDC_DECIMALS;
    uint256 b = 1 << 192;
    uint256 uintPrice = a / b;
    return (1 ether * 1e6) / uintPrice;
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

  function _ratio(uint256 wethAmount) internal view returns (uint256) {
    return (wethAmount * usdcPerWeth) / 10 ** ERC20(weth).decimals();
  }

  function _bootstrapLockVanilla() internal {
    (, liquidityAddedVanilla, addedUsdcVanilla, addedWethVanilla) = exit10.bootstrapLock(
      _addLiquidityParams(depositUsdc, depositWeth)
    );
    _assertEqRoughly(addedWethVanilla, depositWeth, 'Vanilla adds all weth');
  }

  function _createBondVanilla() internal {
    (, liquidityAddedVanilla, addedUsdcVanilla, addedWethVanilla) = exit10.createBond(
      _addLiquidityParams(depositUsdc, depositWeth)
    );
  }
}
