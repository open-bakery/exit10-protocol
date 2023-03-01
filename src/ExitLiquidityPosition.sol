// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IUniswapV3Pool.sol';

import './UniswapBase.sol';

contract ExitLiquidityPosition is ERC20, UniswapBase {
  constructor(
    string memory name_,
    string memory symbol_,
    IUniswapBase.BaseDeployParams memory baseParams_
  ) ERC20(name_, symbol_) UniswapBase(baseParams_) {}

  function _initializePool(
    address _tokenA,
    address _tokenB,
    uint24 _fee,
    uint160 sqrtPriceX96
  ) internal returns (address _pool) {
    _pool = FACTORY.getPool(_tokenA, _tokenB, _fee);
    if (_pool == address(0)) {
      _pool = FACTORY.createPool(_tokenA, _tokenB, _fee);
      IUniswapV3Pool(_pool).initialize(sqrtPriceX96);
    } else {
      (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(_pool).slot0();
      if (sqrtPriceX96Existing == 0) {
        IUniswapV3Pool(_pool).initialize(sqrtPriceX96);
      }
    }
  }
}
