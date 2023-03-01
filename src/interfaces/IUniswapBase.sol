// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IUniswapBase {
  struct BaseDeployParams {
    address uniswapFactory;
    address nonfungiblePositionManager;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
  }

  /// @notice AddLiquidity Struct which is responsible for adding liquidity to a position.
  /// @dev depositor The address which the position will be credited to.

  struct AddLiquidity {
    address depositor;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct RemoveLiquidity {
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }
}
