// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
// import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
// import { Exit10, UniswapBase } from '../src/Exit10.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';

contract Exit10_edgeCasesTest is ABaseExit10Test {
  /// @dev Test to see if anyone can add liquidity directly to a position bypassing the position owner and the Exit10 contract.
  function test_addLiquidityBypass() public {
    (uint256 tokenId, , , ) = exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));

    vm.startPrank(alice);
    INPM.IncreaseLiquidityParams memory params = INPM.IncreaseLiquidityParams({
      tokenId: tokenId,
      amount0Desired: 1700_000000,
      amount1Desired: 1 ether,
      amount0Min: 0,
      amount1Min: 0,
      deadline: block.timestamp
    });

    _maxApprove(weth, nonfungiblePositionManager);
    _maxApprove(usdc, nonfungiblePositionManager);

    (uint128 liquidity, , ) = INPM(nonfungiblePositionManager).increaseLiquidity(params);

    assertTrue(liquidity != 0, 'Check liquidity has been added by third party');

    vm.expectRevert();
    INPM(nonfungiblePositionManager).decreaseLiquidity(
      INPM.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.stopPrank();
  }
}
