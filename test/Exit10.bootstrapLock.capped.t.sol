// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test, console } from 'forge-std/Test.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10, UniswapBase } from '../src/Exit10.sol';

contract Exit10_bootstrapLockCappedTest is ABaseExit10Test {
  function test_bootstrapLock_capped() public {
    // liquidity that would be normally added vs cap:
    // 56708918664216
    // 10000000000000

    uint256 amount0 = _tokenAmount(usdc, 1000);
    uint256 amount1 = _tokenAmount(weth, 1);
    uint256 balanceBefore0 = _balance(usdc);
    uint256 balanceBefore1 = _balance(weth);
    (, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(amount0, amount1)
    );

    assertEq(liquidityAdded, _getBootstrapCap());
    assertTrue(exit10.isBootstrapCapReached());
    assertLt(amountAdded0, amount0);
    assertLt(amountAdded1, amount1);

    assertEq(_balance(usdc), balanceBefore0 - amountAdded0);
    assertEq(_balance(weth), balanceBefore1 - amountAdded1);
  }

  function _getBootstrapCap() internal pure override returns (uint256) {
    return 10000000000000;
  }
}
