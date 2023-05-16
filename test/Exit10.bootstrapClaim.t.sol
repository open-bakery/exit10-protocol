// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_bootstrapClaimTest is ABaseExit10Test {
  function test_bootstrapClaim() public {
    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _eth10k();
    (uint256 pending, uint256 reserve, , uint256 bootstrap) = exit10.getBuckets();
    exit10.exit10();

    assertEq(_getLiquidity(), pending + reserve, 'Check liquidity position');

    uint256 balanceBeforeOut = _balance(exit10.TOKEN_OUT());
    uint256 bootBalance = _balance(boot);
    exit10.bootstrapClaim();

    uint256 claimableAmount = Math.mulDiv(
      (bootBalance / exit10.TOKEN_MULTIPLIER()),
      exit10.bootstrapRewardsPlusRefund(),
      bootstrap,
      Math.Rounding.Down
    );

    assertEq(_balance(boot), 0, 'BOOT tokens burned');
    assertGt(claimableAmount, 0, 'Check claimable > 0');
    assertEq(_balance(exit10.TOKEN_OUT()), balanceBeforeOut + claimableAmount, 'balance out increased');
  }

  function test_bootstrapClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.bootstrapClaim();
  }
}
