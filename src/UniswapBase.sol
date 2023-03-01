// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IUniswapV3Pool.sol';
import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/IUniswapBase.sol';

contract UniswapBase is IUniswapBase {
  IUniswapV3Factory public immutable FACTORY;
  IUniswapV3Pool public immutable POOL;
  address public immutable NPM;
  address public immutable TOKEN_IN;
  address public immutable TOKEN_OUT;
  uint24 public immutable FEE;
  int24 public immutable TICK_LOWER;
  int24 public immutable TICK_UPPER;

  uint256 public positionId;

  constructor(BaseDeployParams memory params) {
    FACTORY = IUniswapV3Factory(params.uniswapFactory);
    TOKEN_IN = params.tokenIn;
    TOKEN_OUT = params.tokenOut;
    FEE = params.fee;
    NPM = params.nonfungiblePositionManager;
    POOL = IUniswapV3Pool(FACTORY.getPool(params.tokenIn, params.tokenOut, params.fee));
    TICK_LOWER = params.tickLower;
    TICK_UPPER = params.tickUpper;
  }

  function _addLiquidity(AddLiquidity memory _params)
    internal
    returns (
      uint256 _tokenId,
      uint128 _liquidityAdded,
      uint256 _amountAdded0,
      uint256 _amountAdded1
    )
  {
    (address token0, address token1) = TOKEN_IN < TOKEN_OUT ? (TOKEN_IN, TOKEN_OUT) : (TOKEN_OUT, TOKEN_IN);

    if (positionId == 0) {
      (_tokenId, _liquidityAdded, _amountAdded0, _amountAdded1) = INPM(NPM).mint(
        INPM.MintParams({
          token0: token0,
          token1: token1,
          fee: FEE,
          tickLower: TICK_LOWER, //Tick needs to exist (right spacing)
          tickUpper: TICK_UPPER, //Tick needs to exist (right spacing)
          amount0Desired: _params.amount0Desired,
          amount1Desired: _params.amount1Desired,
          amount0Min: _params.amount0Min, // slippage check
          amount1Min: _params.amount1Min, // slippage check
          recipient: address(this), // receiver of ERC721
          deadline: _params.deadline
        })
      );
      positionId = _tokenId;
    } else {
      (_liquidityAdded, _amountAdded0, _amountAdded1) = INPM(NPM).increaseLiquidity(
        INPM.IncreaseLiquidityParams({
          tokenId: positionId,
          amount0Desired: _params.amount0Desired,
          amount1Desired: _params.amount1Desired,
          amount0Min: _params.amount0Min,
          amount1Min: _params.amount1Min,
          deadline: _params.deadline
        })
      );
    }
  }

  function _decreaseLiquidity(RemoveLiquidity memory _params)
    internal
    returns (uint256 _amountRemoved0, uint256 _amountRemoved1)
  {
    (_amountRemoved0, _amountRemoved1) = INPM(NPM).decreaseLiquidity(
      INPM.DecreaseLiquidityParams({
        tokenId: positionId,
        liquidity: _params.liquidity,
        amount0Min: _params.amount0Min,
        amount1Min: _params.amount1Min,
        deadline: _params.deadline
      })
    );
  }

  function _collect(
    address _recipient,
    uint128 _amount0Max,
    uint128 _amount1Max
  ) internal returns (uint256 _amountCollected0, uint256 _amountCollected1) {
    if (positionId == 0) return (0, 0);
    (_amountCollected0, _amountCollected1) = INPM(NPM).collect(
      INPM.CollectParams({
        tokenId: positionId,
        recipient: _recipient,
        amount0Max: _amount0Max,
        amount1Max: _amount1Max
      })
    );
  }
}
