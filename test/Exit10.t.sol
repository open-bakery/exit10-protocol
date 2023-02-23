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
  uint256 _accrualParameter = 1 days;
  uint256 _bootstrapPeriod = 1 hours;
  uint256 _lpPerUSD = 10000000; // made up number

  ERC20 token0;
  ERC20 token1;
  uint256 deployTime;
  uint256 constant MX = type(uint256).max;
  uint256 boot_multiplier;

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
        bootstrapPeriod: _bootstrapPeriod,
        accrualParameter: _accrualParameter,
        lpPerUSD: _lpPerUSD
      })
    );
    boot_multiplier = exit10.BOOT_MULTIPLIER();
    deployTime = block.timestamp;
    token0 = ERC20(exit10.POOL().token0());
    token1 = ERC20(exit10.POOL().token1());
    _mintAndApprove(address(token0), MX);
    _mintAndApprove(address(token1), MX);
  }

  function testSetup() public {
    assertTrue(exit10.positionId0() == 0, 'Check positionId0');
    assertTrue(exit10.positionId1() == 0, 'Check positionId1');
    assertTrue(exit10.countChickenIn() == 0, 'Check countChickenIn');
    assertTrue(exit10.countChickenOut() == 0, 'Check countChickenOut');
    assertTrue(exit10.inExitMode() == false, 'Check inExitMode');
    assertTrue(token0.balanceOf(address(this)) == MX);
    assertTrue(token1.balanceOf(address(this)) == MX);
  }

  function testBootstrapLock() public {
    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      address(this),
      IExit10.AddLiquidity({
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(amountAdded0 == MX - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(amountAdded1 == MX - token1.balanceOf(address(this)), 'Check amountAdded1');
    assertTrue(tokenId == exit10.positionId1(), 'Check positionId1');
    assertTrue(liquidityAdded != 0, 'Check liquidityAdded');
    assertTrue(ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * boot_multiplier, 'Check BOOT balance');
  }

  function testBootstrapRevert() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    vm.expectRevert(bytes('EXIT10: Bootstrap ended'));
    exit10.bootstrapLock(
      address(this),
      IExit10.AddLiquidity({
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _mintAndApprove(address _token, uint256 _amount) internal {
    deal(_token, address(this), _amount);
    ERC20(_token).approve(address(exit10), _amount);
  }

  function _createBond(uint256 _amount) internal returns (uint256 _bondId) {
    skip(_bootstrapPeriod);
  }

  function checkTreasury(
    uint256 pending,
    uint256 reserve,
    uint256 exit,
    uint256 bootstrap
  ) internal {
    (uint256 _pending, uint256 _reserve, uint256 _exit, uint256 _bootstrap) = exit10.getTreasury();
    assertTrue(pending == _pending, 'Pending bucket check');
    assertTrue(reserve == _reserve, 'Reserve bucket check');
    assertTrue(exit == _exit, 'Exit bucket check');
    assertTrue(bootstrap == _bootstrap, 'Bootstrap bucket check');
  }

  function checkBondData(
    uint256 bondId,
    uint256 bondAmount,
    uint256 claimedBoostAmount,
    uint64 startTime,
    uint64 endTime,
    uint8 status
  ) internal {
    (uint256 _lockedAmount, uint256 _claimedBondToken, uint64 _startTime, uint64 _endTime, uint8 _status) = exit10
      .getBondData(bondId);
    assertTrue(_lockedAmount == bondAmount, 'Check bond amount');
    assertTrue(_claimedBondToken == claimedBoostAmount, 'Check claimed boosted tokens');
    assertTrue(_startTime == startTime, 'Check startTime');
    assertTrue(_endTime == endTime, 'Check endTime');
    assertTrue(_status == status, 'Check status');
  }
}
