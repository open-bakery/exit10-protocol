// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseExit10Test, FeeSplitter } from './ABaseExit10.t.sol';
import { ILido } from '../src/interfaces/ILido.sol';

contract Exit10_exitClaimTest is ABaseExit10Test {
  function test_exitClaim() public {
    uint256 delta = 1;
    // setup: create bond for myself and alice, skip sime time to accumulate fees
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();

    vm.startPrank(alice);
    (uint256 bondIdAlice, uint256 bondAmountAlice) = _createBond(alice);
    skip(100);
    exit10.convertBond(bondIdAlice, _removeLiquidityParams(bondAmountAlice));
    uint256 blpBalanceAlice = blp.balanceOf(address(alice));
    blp.approve(address(masterchefExit), type(uint).max);
    masterchefExit.deposit(1, blpBalanceAlice);
    vm.stopPrank();

    _generateFees(token0, token1, _tokenAmount(token0, 100_000_000));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    uint256 blpBalance = blp.balanceOf(address(this));
    blp.approve(address(masterchefExit), type(uint).max);
    masterchefExit.deposit(1, blpBalance);

    FeeSplitter(feeSplitter).updateFees(0);
    assertGt(_balance(exit10.TOKEN_IN(), address(exit10)), 0, 'Check balance of tokenIn in Exit10');

    // exit10
    _eth10k();
    exit10.exit10();

    uint256 precision = 1e18;
    uint256 initialBalanceTokenOut = _balance(exit10.TOKEN_OUT());
    uint256 initialBalanceTokenIn = _balance(exit10.TOKEN_IN());
    uint256 initialLidoShare = ILido(exit10.LIDO()).sharesOf(address(exit10));
    uint256 initialBalanceExitTokenIn = _balance(exit10.TOKEN_IN(), address(exit10));

    vm.prank(alice);
    masterchefExit.withdraw(1, blpBalanceAlice);
    masterchefExit.withdraw(1, blpBalance);
    assertGt(_balance(exit), 0, 'Check exit balance');
    assertGt(_balance(exit, alice), 0, 'Check exit balance');
    uint256 exitTokenShare = (_balance(exit) * precision) / exit.totalSupply();

    // claim as alice first so that we don't start with zero
    vm.prank(alice);
    exit10.exitClaim();

    // action!
    exit10.exitClaim();

    assertEq(_balance(exit), 0, 'Check exit burn');
    assertEq(
      _balance(exit10.TOKEN_OUT()),
      initialBalanceTokenOut + (exit10.exitTokenRewardsFinal() * exitTokenShare) / precision,
      'Check TOKEN_OUT balance'
    );
    assertApproxEqAbs(
      _balance(exit10.TOKEN_IN()),
      initialBalanceTokenIn + ((initialBalanceExitTokenIn * exitTokenShare) / precision),
      delta,
      'Check TOKEN_IN balance'
    );
    assertApproxEqAbs(
      ILido(exit10.LIDO()).sharesOf(address(this)),
      (initialLidoShare * exitTokenShare) / precision,
      delta,
      'Check Lido share'
    );
    assertGt(_balance(exit10.TOKEN_IN()), initialBalanceTokenIn, 'Check increase in tokenIn');
  }

  function test_exitClaim_RevertIf_NotExited() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.exitClaim();
  }
}
