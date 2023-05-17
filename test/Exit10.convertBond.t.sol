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
    assertEq(_balance(exit), _getExitAmount(exitBucket), 'Check exit minted');
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

  function test_convertBond_RevertIf_StatusInExitMode() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    _createBond();
    _eth10k();
    exit10.exit10();
    vm.expectRevert(bytes('EXIT10: In Exit mode'));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
  }

  function test_convertBond_claimAndDistributeFees() public {
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();
    _generateFees(token0, token1, _tokenAmount(address(token0), 1000));
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    assertGt(_balance(token0, feeSplitter), 0, 'Check balance0 feeSplitter');
    assertGt(_balance(token1, feeSplitter), 0, 'Check balance1 feeSplitter');
  }

  function test_convertBond_mintMaxExitCap() public {
    (uint256 amount0, uint256 amount1) = (exit10.TOKEN_OUT() < exit10.TOKEN_IN())
      ? (_tokenAmount(exit10.TOKEN_OUT(), 100_000_000), _tokenAmount(exit10.TOKEN_IN(), 1_000_000))
      : (_tokenAmount(exit10.TOKEN_IN(), 1_000_000), _tokenAmount(exit10.TOKEN_OUT(), 100_000_000));

    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond(amount0, amount1);
    exit10.convertBond(bondId, _removeLiquidityParams(bondAmount));
    assertEq(exit.totalSupply(), exit10.MAX_EXIT_SUPPLY(), 'Check exit token capmint');
    assertEq(exit.balanceOf(address(this)), exit10.BONDERS_EXIT_REWARD(), 'Check exit balance');
  }
}
