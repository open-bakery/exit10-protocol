// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IUniswapV3Router } from '../src/interfaces/IUniswapV3Router.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';
import { IWETH9 } from '../src/interfaces/IWETH9.sol';
import { IExit10, IUniswapBase, Exit10, UniswapBase } from './Exit10.sol';

contract DepositHelper {
  using SafeERC20 for IERC20;
  uint256 private constant MAX_UINT_256 = type(uint256).max;
  address immutable UNISWAP_V3_ROUTER;
  address immutable EXIT_10;
  address immutable WETH;

  uint256 private constant DEADLINE = 1e10;

  constructor(address uniswapV3Router_, address exit10_, address weth_) {
    UNISWAP_V3_ROUTER = uniswapV3Router_;
    EXIT_10 = exit10_;
    WETH = weth_;
  }

  function swapAndBootstrapLock(
    uint256 initialAmount0,
    uint256 initialAmount1,
    IUniswapV3Router.ExactInputSingleParams memory swapParams
  ) external payable {
    (address token0, address token1) = _sortAndDeposit(
      swapParams.tokenIn,
      swapParams.tokenOut,
      initialAmount0,
      initialAmount1
    );
    Exit10(EXIT_10).bootstrapLock(_swap(token0, token1, initialAmount0, initialAmount1, swapParams));
  }

  function swapAndCreateBond(
    uint256 initialAmount0,
    uint256 initialAmount1,
    IUniswapV3Router.ExactInputSingleParams memory swapParams
  ) external payable {
    (address token0, address token1) = _sortAndDeposit(
      swapParams.tokenIn,
      swapParams.tokenOut,
      initialAmount0,
      initialAmount1
    );
    Exit10(EXIT_10).createBond(_swap(token0, token1, initialAmount0, initialAmount1, swapParams));
  }

  function _processEth(
    address _token0,
    address _token1,
    uint256 _initialAmount0,
    uint256 _initialAmount1,
    uint256 _msgValue
  ) internal returns (uint _amount0, uint _amount1) {
    _amount0 = _initialAmount0;
    _amount1 = _initialAmount1;

    IWETH9(WETH).deposit{ value: _msgValue }();
    if (_token0 == WETH) {
      _amount0 += _msgValue;
    } else if (_token1 == WETH) {
      _amount1 += _msgValue;
    }
  }

  function _swap(
    address _token0,
    address _token1,
    uint256 _initialAmount0,
    uint256 _initialAmount1,
    IUniswapV3Router.ExactInputSingleParams memory _swapParams
  ) internal returns (IUniswapBase.AddLiquidity memory _params) {
    if (msg.value != 0) {
      (_initialAmount0, _initialAmount1) = _processEth(_token0, _token1, _initialAmount0, _initialAmount1, msg.value);
    }

    _approveTokens(_token0, _token1, UNISWAP_V3_ROUTER, _initialAmount0, _initialAmount1);

    uint256 amountOut = IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(_swapParams);

    if (_swapParams.tokenIn == _token0) {
      _initialAmount0 -= _swapParams.amountIn;
      _initialAmount1 += amountOut;
    } else {
      _initialAmount1 -= _swapParams.amountIn;
      _initialAmount0 += amountOut;
    }

    _approveTokens(_token0, _token1, EXIT_10, _initialAmount0, _initialAmount1);

    _params = IUniswapBase.AddLiquidity({
      depositor: msg.sender,
      amount0Desired: _initialAmount0,
      amount1Desired: _initialAmount1,
      amount0Min: 0,
      amount1Min: 0,
      deadline: DEADLINE
    });
  }

  function _sortAndDeposit(
    address _tokenA,
    address _tokenB,
    uint256 _amount0,
    uint256 _amount1
  ) internal returns (address _token0, address _token1) {
    (_token0, _token1) = _tokenSort(_tokenA, _tokenB);
    _depositTokens(_token0, _token1, _amount0, _amount1);
  }

  function _depositTokens(address _token0, address _token1, uint256 _amount0, uint256 _amount1) internal {
    if (_amount0 != 0) IERC20(_token0).safeTransferFrom(msg.sender, address(this), _amount0);
    if (_amount1 != 0) IERC20(_token1).safeTransferFrom(msg.sender, address(this), _amount1);
  }

  function _approveTokens(
    address _token0,
    address _token1,
    address _spender,
    uint256 _amount0,
    uint256 _amount1
  ) internal {
    _approve(_token0, _spender, _amount0);
    _approve(_token1, _spender, _amount1);
  }

  function _approve(address _token, address _spender, uint256 _amount) internal {
    if (IERC20(_token).allowance(address(this), _spender) < _amount) IERC20(_token).approve(_spender, MAX_UINT_256);
  }

  function _tokenSort(address _tokenA, address _tokenB) internal pure returns (address _token0, address _token1) {
    (_token0, _token1) = (_tokenA < _tokenB) ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
  }
}
