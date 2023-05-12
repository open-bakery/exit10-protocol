// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IUniswapV3Router } from '../src/interfaces/IUniswapV3Router.sol';
import { IUniswapV2Factory } from '../src/interfaces/IUniswapV2Factory.sol';
import { IUniswapV2Router } from '../src/interfaces/IUniswapV2Router.sol';
import { Exit10 } from '../src/Exit10.sol';

abstract contract ABaseTest is Test {
  uint256 constant MAX_UINT_256 = type(uint256).max;
  uint256 constant RESOLUTION = 10000;
  address constant ZERO_ADDRESS = address(0);

  address me = address(this);
  address alice = address(0x0a);
  address bob = address(0x0b);
  address charlie = address(0x0c);

  IUniswapV2Factory immutable UNISWAP_V2_FACTORY = IUniswapV2Factory(vm.envAddress('UNISWAP_V2_FACTORY'));
  IUniswapV2Router immutable UNISWAP_V2_ROUTER = IUniswapV2Router(vm.envAddress('UNISWAP_V2_ROUTER'));
  IUniswapV3Router immutable UNISWAP_V3_ROUTER = IUniswapV3Router(vm.envAddress('UNISWAP_V3_ROUTER'));

  function _checkBalances(
    address _holder,
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1
  ) internal {
    assertEq(ERC20(_token0).balanceOf(_holder), _amount0, 'Check balance 0');
    assertEq(ERC20(_token1).balanceOf(_holder), _amount1, 'Check balance 1');
  }

  function _mintAndApprove(address _token, uint256 _amount, address _spender) internal {
    deal(_token, address(this), _amount);
    _maxApprove(_token, _spender);
  }

  function _mintAndApprove(address to, address _token, uint256 _amount, address _spender) internal {
    deal(_token, to, _amount);
    vm.prank(to);
    _maxApprove(_token, _spender);
  }

  function _mintAndApprove(ERC20 _token, uint256 _amount, address _spender) internal {
    deal(address(_token), address(this), _amount);
    _maxApprove(address(_token), _spender);
  }

  function _mintAndApprove(address to, ERC20 _token, uint256 _amount, address _spender) internal {
    deal(address(_token), to, _amount);
    vm.prank(to);
    _maxApprove(address(_token), _spender);
  }

  function _maxApproveFrom(address _from, address _token, address _spender) internal {
    vm.startPrank(_from);
    ERC20(_token).approve(_spender, type(uint256).max);
    vm.stopPrank();
  }

  function _maxApprove(address _token, address _spender) internal {
    ERC20(_token).approve(_spender, type(uint256).max);
  }

  function _maxApprove(address _token1, address _token2, address _spender) internal {
    ERC20(_token1).approve(_spender, type(uint256).max);
    ERC20(_token2).approve(_spender, type(uint256).max);
  }

  function _generateFees(address _tokenA, address _tokenB, uint256 _amountA) internal {
    deal(_tokenA, address(this), _amountA);
    uint256 amountOut = _swap(_tokenA, _tokenB, _amountA);
    _swap(_tokenB, _tokenA, amountOut / 2);
  }

  function _generateFees(ERC20 _tokenA, ERC20 _tokenB, uint256 _amountA) internal {
    address tokenA = address(_tokenA);
    address tokenB = address(_tokenB);
    deal(tokenA, address(this), _amountA);
    uint256 amountOut = _swap(tokenA, tokenB, _amountA);
    _swap(tokenB, tokenA, amountOut / 2);
  }

  function _swap(address _in, address _out, uint256 _amount) internal returns (uint256 _amountOut) {
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

  function _tokenAmount(address _token, uint256 _amount) internal view returns (uint256) {
    return _amount * 10 ** ERC20(_token).decimals();
  }

  function _tokenAmount(ERC20 _token, uint256 _amount) internal view returns (uint256) {
    return _amount * 10 ** _token.decimals();
  }

  function _getTokensBalance(
    address _tokenA,
    address _tokenB
  ) internal view returns (uint256 _balanceA, uint256 _balanceB) {
    _balanceA = ERC20(_tokenA).balanceOf(address(this));
    _balanceB = ERC20(_tokenB).balanceOf(address(this));
  }

  function _addPercentToAmount(uint256 _amount, uint256 _percentage) internal pure returns (uint256) {
    return _amount + ((_amount * _percentage) / RESOLUTION);
  }

  function _getTokensBalance(
    ERC20 _tokenA,
    ERC20 _tokenB
  ) internal view returns (uint256 _balanceA, uint256 _balanceB) {
    _balanceA = _tokenA.balanceOf(address(this));
    _balanceB = _tokenB.balanceOf(address(this));
  }

  function _balance(ERC20 _token) internal view returns (uint256) {
    return _token.balanceOf(address(this));
  }

  function _balance(address _token) internal view returns (uint256) {
    return ERC20(_token).balanceOf(address(this));
  }

  function _balance(ERC20 _token, address _who) internal view returns (uint256) {
    return _token.balanceOf(_who);
  }

  function _balance(address _token, address _who) internal view returns (uint256) {
    return ERC20(_token).balanceOf(_who);
  }

  function _ethBalance() internal view returns (uint256) {
    return address(this).balance;
  }

  function _assertEqRoughly(uint256 _a, uint256 _b, string memory _err) internal {
    uint256 precision = 1_000_000;
    if (_a > _b) {
      assertLt(_a - _b, precision, _err);
    } else {
      assertLt(_b - _a, precision, _err);
    }
  }

  function _pairForUniswapV2(address _factory, address _tokenA, address _tokenB) internal pure returns (address _pair) {
    (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    _pair = address(
      uint160(
        uint(
          keccak256(
            abi.encodePacked(
              hex'ff',
              _factory,
              keccak256(abi.encodePacked(token0, token1)),
              hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            )
          )
        )
      )
    );
  }
}
