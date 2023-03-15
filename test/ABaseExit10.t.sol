// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'forge-std/Test.sol';

import './ABase.t.sol';
import '../src/Exit10.sol';
import { MasterchefExit } from '../src/Exit10.sol';

abstract contract ABaseExit10Test is Test, ABaseTest {
  function _skipBootAndCreateBond(Exit10 _exit10) internal returns (uint256 _bondId) {
    skip(_exit10.BOOTSTRAP_PERIOD());
    _bondId = _createBond(_exit10, 10_000_000000, 10 ether);
  }

  function _createBond(Exit10 _exit10, uint256 _amount0, uint256 _amount1) internal returns (uint256 _bondId) {
    (_bondId, , , ) = _exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: _amount0,
        amount1Desired: _amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _setUpExitPool(Exit10 _exit10, address _lp) internal {
    MasterchefExit(_exit10.MASTERCHEF()).add(100, _lp);
    _distributeInitialExitRewards(_exit10);
    MasterchefExit(_exit10.MASTERCHEF()).renounceOwnership();
  }

  function _distributeInitialExitRewards(Exit10 _exit10) internal {
    _exit10.EXIT().mint(_exit10.MASTERCHEF(), _exit10.LP_EXIT_REWARD());
    MasterchefExit(_exit10.MASTERCHEF()).updateRewards(_exit10.LP_EXIT_REWARD());
  }

  function _liquidity(uint256 _positionId, Exit10 _exit10) internal view returns (uint128 _liq) {
    (, , , , , , , _liq, , , , ) = INPM(_exit10.NPM()).positions(_positionId);
  }

  function _currentTick(Exit10 _exit10) internal view returns (int24 _tick) {
    (, _tick, , , , , ) = _exit10.POOL().slot0();
  }

  function _eth10k(Exit10 _exit10) internal {
    _swap(_exit10.TOKEN_OUT(), _exit10.TOKEN_IN(), 200_000_000_000000);
  }

  function _checkBuckets(
    Exit10 _exit10,
    uint256 _pending,
    uint256 _reserve,
    uint256 _exit,
    uint256 _bootstrap
  ) internal {
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = _exit10.getBuckets();
    assertTrue(pending == _pending, 'Treasury: Pending bucket check');
    assertTrue(reserve == _reserve, 'Treasury: Reserve bucket check');
    assertTrue(exit == _exit, 'Treasury: Exit bucket check');
    assertTrue(bootstrap == _bootstrap, 'Treasury: Bootstrap bucket check');
  }

  function _checkBondData(
    Exit10 _exit10,
    uint256 _bondId,
    uint256 _bondAmount,
    uint256 _claimedBoostAmount,
    uint64 _startTime,
    uint64 _endTime,
    uint8 _status
  ) internal {
    (uint256 bondAmount, uint256 claimedBoostToken, uint64 startTime, uint64 endTime, uint8 status) = _exit10
      .getBondData(_bondId);
    assertTrue(bondAmount == _bondAmount, 'Check bond amount');
    assertTrue(claimedBoostToken == _claimedBoostAmount, 'Check claimed boosted tokens');
    assertTrue(startTime == _startTime, 'Check startTime');
    assertTrue(endTime == _endTime, 'Check endTime');
    assertTrue(status == _status, 'Check status');
  }
}
