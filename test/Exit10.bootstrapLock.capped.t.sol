// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { UniswapBase } from '../src/UniswapBase.sol';

contract Exit10_bootstrapLockCappedTest is ABaseExit10Test {
  function test_bootstrapLock_capped() public {
    // Liquidity that would be normally added vs cap:
    // Liquidity per USDC 12875978289:1000000
    // Cap 10_000_000 = 128759782890000000 Liquidity @ ETH 10K

    (uint256 amount0, uint256 amount1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), _tokenAmount(exit10.TOKEN_IN(), 10_000))
      : (_tokenAmount(exit10.TOKEN_IN(), 10_000), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));

    uint256 balanceBefore0 = _balance(address(token0));
    uint256 balanceBefore1 = _balance(address(token1));
    (, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(amount0, amount1)
    );

    assertEq(liquidityAdded, _getBootstrapCap());
    assertTrue(exit10.isBootstrapCapReached());
    assertLt(amountAdded0, amount0);
    assertLt(amountAdded1, amount1);

    assertEq(_balance(address(token0)), balanceBefore0 - amountAdded0, 'check balance 0');
    assertEq(_balance(address(token1)), balanceBefore1 - amountAdded1, 'check balance 1');
  }

  function test_bootstrapLock_capped_tokenOutAmount() public {
    // Liquidity that would be normally added vs cap:
    // Liquidity per USDC 12875978289:1000000
    // Cap 10_000_000 = 128759782890000000 Liquidity @ ETH 10K

    (uint256 amount0, uint256 amount1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), _tokenAmount(exit10.TOKEN_IN(), 10_000))
      : (_tokenAmount(exit10.TOKEN_IN(), 10_000), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));

    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
    _eth10k();
    exit10.exit10();
    uint256 tokenOutBalance = _balance(exit10.TOKEN_OUT(), address(exit10));

    assertApproxEqRel(
      tokenOutBalance,
      _tokenAmount(exit10.TOKEN_OUT(), 10_000_000),
      0.01 ether,
      'Check TOKEN_OUT after exit10'
    );
  }

  function test_bootstrapLock_capped_revertIf_capReached() public {
    (uint256 amount0, uint256 amount1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), _tokenAmount(exit10.TOKEN_IN(), 10_000))
      : (_tokenAmount(exit10.TOKEN_IN(), 10_000), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));
    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));

    assertTrue(exit10.isBootstrapCapReached());
    UniswapBase.AddLiquidity memory params = _addLiquidityParams(amount0, amount1);
    vm.expectRevert(bytes('EXIT10: Bootstrap cap reached'));
    exit10.bootstrapLock(params);
  }

  function test_bootstrapLock_capped_revertIf_createBondBeforebootstrapDurationOver() public {
    (uint256 amount0, uint256 amount1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 10_000_000), _tokenAmount(exit10.TOKEN_IN(), 10_000))
      : (_tokenAmount(exit10.TOKEN_IN(), 10_000), _tokenAmount(exit10.TOKEN_OUT(), 10_000_000));
    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));

    assertTrue(exit10.isBootstrapCapReached());
    UniswapBase.AddLiquidity memory params = _addLiquidityParams(amount0, amount1);
    vm.expectRevert(bytes('EXIT10: Bootstrap ongoing'));
    exit10.createBond(params);
  }

  function _getBootstrapCap() internal pure override returns (uint256) {
    return 128759782890000000;
  }
}
