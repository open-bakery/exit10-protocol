// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_bootstrapLockCappedTest is ABaseExit10Test {
  function test_bootstrapLock_capped() public {
    // Liquidity that would be normally added vs cap:
    // Liquidity per USDC 12875978289:1000000
    // Cap 10_000_000 = 128759782890000000 Liquidity @ ETH 10K

    uint256 amount0 = _tokenAmount(usdc, 10_000_000);
    uint256 amount1 = _tokenAmount(weth, 10_000);
    uint256 balanceBefore0 = _balance(usdc);
    uint256 balanceBefore1 = _balance(weth);
    (, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(amount0, amount1)
    );

    assertEq(liquidityAdded, bootstrapCap);
    assertTrue(exit10.isBootstrapCapReached());
    assertLt(amountAdded0, amount0);
    assertLt(amountAdded1, amount1);

    assertEq(_balance(usdc), balanceBefore0 - amountAdded0);
    assertEq(_balance(weth), balanceBefore1 - amountAdded1);
  }
}
