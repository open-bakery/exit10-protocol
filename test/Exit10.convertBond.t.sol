// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';
import { Exit10 } from '../src/Exit10.sol';

contract Exit10_convertBondTest is ABaseExit10Test {
  function test_ConvertBond() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    uint64 startTime = uint64(block.timestamp);
    uint256 liquidity = _getLiquidity();
    skip(accrualParameter); // skips to half

    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    uint64 endTime = uint64(block.timestamp);
    uint256 exitBucket = _getLiquidity() - (liquidity / 2);

    assertEq(_balance(blp), (liquidity / 2) * exit10.TOKEN_MULTIPLIER(), 'BLP balance');
    assertEq(_balance(exit), _getDiscountedExitAmount(liquidity / 2, exitDiscount), 'Check exit bucket');
    assertEq(_balance(blp), (liquidity / 2) * exit10.TOKEN_MULTIPLIER(), 'BLP balance');

    _checkBalancesExit10(0, 0);
    _checkBondData(
      bondId,
      liquidity,
      (liquidity / 2) * exit10.TOKEN_MULTIPLIER(),
      startTime,
      endTime,
      uint8(Exit10.BondStatus.converted)
    );
    _checkBuckets(0, liquidity / 2, exitBucket, 0);
  }

  function test_convertBond_RevertIf_NotBondOwner() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    vm.prank(address(0xdead));

    vm.expectRevert(bytes('EXIT10: Caller must own the bond'));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
  }

  function test_convertBond_RevertIf_StatusIsCanceled() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.cancelBond(bondId, _removeLiquidityParams(bondAmount));

    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
  }

  function test_convertBond_RevertIf_StatusIsConverted() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
  }
}
