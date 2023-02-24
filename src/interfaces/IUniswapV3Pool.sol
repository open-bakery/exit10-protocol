// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IUniswapV3Pool {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function fee() external view returns (uint24);

  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint8 feeProtocol,
      bool unlocked
    );
}
