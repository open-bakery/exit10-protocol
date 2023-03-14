// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'forge-std/Test.sol';

import '../src/interfaces/IUniswapV3Router.sol';
import '../src/interfaces/IUniswapV2Factory.sol';
import '../src/interfaces/IUniswapV2Router.sol';

import '../src/Exit10.sol';

abstract contract ABaseTest is Test {
  IUniswapV2Factory immutable UNISWAP_V2_FACTORY = IUniswapV2Factory(vm.envAddress('UNISWAP_V2_FACTORY'));
  IUniswapV2Router immutable UNISWAP_V2_ROUTER = IUniswapV2Router(vm.envAddress('UNISWAP_V2_ROUTER'));
  IUniswapV3Router UNISWAP_V3_ROUTER = IUniswapV3Router(vm.envAddress('UNISWAP_V3_ROUTER'));

  function _tokenAmount(address _token, uint256 _amount) internal view returns (uint256) {
    return _amount * 10**ERC20(_token).decimals();
  }

  function _getTokensBalance(address _tokenA, address _tokenB)
    internal
    view
    returns (uint256 _balanceA, uint256 _balanceB)
  {
    _balanceA = ERC20(_tokenA).balanceOf(address(this));
    _balanceB = ERC20(_tokenB).balanceOf(address(this));
  }

  function _checkBalances(
    address _holder,
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1
  ) internal {
    assertTrue(ERC20(_token0).balanceOf(_holder) == _amount0, 'Check balance 0');
    assertTrue(ERC20(_token1).balanceOf(_holder) == _amount1, 'Check balance 1');
  }

  function _mintAndApprove(
    address _token,
    uint256 _amount,
    address _spender
  ) internal {
    deal(_token, address(this), _amount);
    _maxApprove(_token, _spender);
  }

  function _maxApprove(address _token, address _spender) internal {
    ERC20(_token).approve(_spender, type(uint256).max);
  }

  function _generateFees(
    address _tokenA,
    address _tokenB,
    uint256 _amountA
  ) internal {
    deal(_tokenA, address(this), _amountA);
    uint256 amountOut = _swap(_tokenA, _tokenB, _amountA);
    _swap(_tokenB, _tokenA, amountOut / 2);
  }

  function _swap(
    address _in,
    address _out,
    uint256 _amount
  ) internal returns (uint256 _amountOut) {
    _amountOut = UNISWAP_V3_ROUTER.exactInputSingle(
      IUniswapV3Router.ExactInputSingleParams({
        tokenIn: _in,
        tokenOut: _out,
        fee: 500,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: _amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );
  }
}