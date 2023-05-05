// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { console } from 'forge-std/console.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10 } from '../src/Exit10.sol';
import { DepositHelper } from '../src/DepositHelper.sol';
import { IUniswapV3Router } from '../src/interfaces/IUniswapV3Router.sol';
import { IUniswapV3Pool } from '../src/UniswapBase.sol';
// needs v3-core@0.8
import { TickMath } from '../lib/v3-core/contracts/libraries/TickMath.sol';
import { FullMath } from '../lib/v3-core/contracts/libraries/FullMath.sol';
import { LiquidityAmounts } from '../lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

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

  function testPriceLimitSwaps() public {
    _skipBootstrap();
    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    (uint160 sqrtRatioX96, int24 tick, , , , , ) = IUniswapV3Pool(vm.envAddress('POOL')).slot0();
    console.log('initial USDC balance of DepositHelper:', ERC20(usdc).balanceOf(address(depositHelper)));
    console.log('sqrtRatioX96:', sqrtRatioX96);
    (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtRatioX96,
      sqrtRatioAX96,
      sqrtRatioBX96,
      1e15
    ); // amounts to obtain 1e15 liquidity
    uint256 swapAmount0 = convert1ToToken0(sqrtRatioX96, amount1, 6); // usdc amount to swap
    ERC20(usdc).transfer(alice, amount0 + swapAmount0); // give usdc to alice
    IUniswapV3Router.ExactInputSingleParams memory swapParams = _getSwapParams(usdc, weth, swapAmount0);
    swapParams.sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(tick - 1);
    console.log('alice sends', amount0 + swapAmount0, 'USDC');
    console.log('and swaps', swapAmount0, 'USDC for ETH');
    console.log('swapParams.sqrtPriceLimitX96 set to:', swapParams.sqrtPriceLimitX96);
    vm.startPrank(alice);
    ERC20(usdc).approve(address(depositHelper), amount0 + swapAmount0);
    depositHelper.swapAndCreateBond(amount0 + swapAmount0, 0, swapParams);
    vm.stopPrank();
    uint256 usdcLeft = ERC20(usdc).balanceOf(address(depositHelper));
    console.log('Only', swapAmount0 - usdcLeft, 'USDC has been swapped and used to mint bonds');
    console.log('USDC Left into DepositHelper:', usdcLeft);
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

  function sqrtPriceX96ToUint(uint160 _sqrtPriceX96, uint8 decimalsToken0) internal pure returns (uint256) {
    uint256 numerator1 = uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96);
    uint256 numerator2 = 10 ** decimalsToken0;
    return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
  }

  function convert0ToToken1(
    uint160 _sqrtPriceX96,
    uint256 amount0,
    uint8 decimalsToken0
  ) internal pure returns (uint256 amount0ConvertedToToken1) {
    uint256 price = sqrtPriceX96ToUint(_sqrtPriceX96, decimalsToken0);
    amount0ConvertedToToken1 = (amount0 * (price)) / (10 ** decimalsToken0);
  }

  function convert1ToToken0(
    uint160 _sqrtPriceX96,
    uint256 amount1,
    uint8 decimalsToken0
  ) internal pure returns (uint256 amount1ConvertedToToken0) {
    uint256 price = sqrtPriceX96ToUint(_sqrtPriceX96, decimalsToken0);
    if (price == 0) return 0;
    amount1ConvertedToToken0 = (amount1 * (10 ** decimalsToken0)) / (price);
  }
}
