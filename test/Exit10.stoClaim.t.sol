// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract Exit10_stoClaimTest is ABaseExit10Test {
  function test_stoClaim() public {
    // give myself and alice some STO
    uint256 stoAmount = _tokenAmount(sto, 1000);
    uint256 stoSupply = sto.MAX_SUPPLY();
    deal(address(sto), me, stoAmount);
    deal(address(sto), alice, stoAmount * 2);

    // accumulate some fees
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    skip(accrualParameter);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));

    // exit10
    _eth10k();
    exit10.exit10();

    // claim as alice first so that we don't start with zero
    vm.prank(alice);
    exit10.stoClaim();

    // record pre-action state
    uint256 initialBalanceTokenOut = _balance(exit10.TOKEN_OUT());
    uint256 precision = 1e18;
    uint256 stoTokenShare = (_balance(sto) * precision) / stoSupply;

    exit10.stoClaim();

    assertEq(_balance(sto), 0, 'STO tokens burned');
    assertEq(
      _balance(exit10.TOKEN_OUT()),
      initialBalanceTokenOut + (exit10.teamPlusBackersRewards() * stoTokenShare) / precision,
      'USD balance increased'
    );
  }

  function test_stoClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.stoClaim();
  }
}
