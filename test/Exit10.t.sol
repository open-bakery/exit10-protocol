// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '../src/Exit10.sol';
import '../src/NFT.sol';
import '../src/interfaces/IExit10.sol';

contract Exit10Test is Test {
  Exit10 exit10;
  NFT nft;

  address _sto;
  address _npm = vm.envAddress('UNISWAP_V3_NPM');
  address _pool = vm.envAddress('POOL');
  int24 _lowerTick = int24(vm.envInt('LOWER_TICK'));
  int24 _upperTick = int24(vm.envInt('UPPER_TICK'));
  uint256 _targetAverageAgeSeconds = 1 days;
  uint256 _initialAccrualParameter = 4217 seconds;
  uint256 _minimumAccrualParameter = 1 seconds;
  uint256 _accrualAdjustmentRate = 0.01 ether; // equeals to 1%
  uint256 _accrualAdjustmentPeriodSeconds = 1 days;
  uint256 _bootstrapPeriod = 1 hours;
  uint256 _lpPerUSD = 10000000; // made up number

  function setUp() public {
    nft = new NFT('Bond Data', 'BND', 0);
    exit10 = new Exit10(
      IExit10.DeployParams({
        NFT: address(nft),
        NPM: _npm,
        STO: _sto,
        pool: _pool,
        tickLower: _lowerTick,
        tickUpper: _upperTick,
        bootstrapPeriod: _bootstrapPeriod, // Min duration of first chicken-in
        targetAverageAgeSeconds: _targetAverageAgeSeconds, // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual
        initialAccrualParameter: _initialAccrualParameter, // Initial value for `accrualParameter`
        minimumAccrualParameter: _minimumAccrualParameter, // Stop adjusting `accrualParameter` when this value is reached
        accrualAdjustmentRate: _accrualAdjustmentRate, // `accrualParameter` is multiplied `1 - accrualAdjustmentRate` every time there's an adjustment
        accrualAdjustmentPeriodSeconds: _accrualAdjustmentPeriodSeconds, // The duration of an adjustment period in seconds
        lpPerUSD: _lpPerUSD
      })
    );
  }

  function test() public {
    assertTrue(exit10.positionId0() == 0, 'Launched');
  }
}
