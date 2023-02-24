// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '../src/Exit10.sol';
import '../src/NFT.sol';
import '../src/STO.sol';
import '../src/interfaces/IExit10.sol';
import '../src/interfaces/ISwapRouter.sol';
import '../src/interfaces/INonfungiblePositionManager.sol';

contract Exit10Test is Test {
  Exit10 exit10;
  NFT nft;
  STO sto;
  ISwapRouter public immutable UNISWAP_ROUTER = ISwapRouter(vm.envAddress('UNISWAP_ROUTER'));

  address _npm = vm.envAddress('UNISWAP_V3_NPM');
  address _pool = vm.envAddress('POOL');
  int24 _lowerTick = int24(vm.envInt('LOWER_TICK'));
  int24 _upperTick = int24(vm.envInt('UPPER_TICK'));
  uint256 _accrualParameter = 1 days;
  uint256 _bootstrapPeriod = 1 hours;
  uint256 _lpPerUSD = 1; // made up number

  ERC20 token0;
  ERC20 token1;
  uint256 deployTime;
  uint256 constant MX = type(uint256).max;

  address _masterchef0 = address(0x0a);
  address _masterchef1 = address(0x0b);
  address _masterchef2 = address(0x0c);

  function setUp() public {
    nft = new NFT('Bond Data', 'BND', 0);
    sto = new STO(vm.envAddress('USDC'));
    exit10 = new Exit10(
      IExit10.DeployParams({
        NFT: address(nft),
        NPM: _npm,
        STO: address(sto),
        pool: _pool,
        masterchef0: _masterchef0,
        masterchef1: _masterchef1,
        masterchef2: _masterchef2,
        tickLower: _lowerTick,
        tickUpper: _upperTick,
        bootstrapPeriod: _bootstrapPeriod,
        accrualParameter: _accrualParameter,
        lpPerUSD: _lpPerUSD
      })
    );
    sto.setExit10(address(exit10));
    nft.setExit10(address(exit10));
    deployTime = block.timestamp;
    token0 = ERC20(exit10.POOL().token0());
    token1 = ERC20(exit10.POOL().token1());
    _mintAndApprove(address(token0), MX);
    _mintAndApprove(address(token1), MX);
    _maxApprove(address(token0), address(UNISWAP_ROUTER));
    _maxApprove(address(token1), address(UNISWAP_ROUTER));
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
      IExit10.AddLiquidity({
        depositor: address(this),
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
    assertTrue(
      ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * exit10.TOKEN_MULTIPLIER(),
      'Check BOOT balance'
    );
    checkTreasury(0, 0, 0, liquidityAdded);
    checkBalances(address(exit10), 0, 0);
  }

  function testBootstrapRevert() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    vm.expectRevert(bytes('EXIT10: Bootstrap ended'));
    exit10.bootstrapLock(
      IExit10.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCreateBondBootstrapOngoingRevert() public {
    vm.expectRevert(bytes('EXIT10: Bootstrap ongoing'));
    exit10.createBond(
      IExit10.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCreateBond() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = _createBond();
    checkBondData(
      bondId,
      _liquidity(exit10.positionId0()),
      0,
      uint64(block.timestamp),
      0,
      uint8(IExit10.BondStatus.active)
    );
    assertTrue(_liquidity(exit10.positionId0()) != 0, 'Check liquidity');
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');
    checkTreasury(uint256(_liquidity(exit10.positionId0())), 0, 0, 0);
    checkBalances(address(exit10), 0, 0);
  }

  function testCreateBondOnBehalfOfUser() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = exit10.createBond(
      IExit10.AddLiquidity({
        depositor: address(0xdead),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(nft.ownerOf(bondId) == address(0xdead), 'Check NFT owner');
  }

  function testChickenOut() public {
    uint256 bondId = _skipBootAndCreateBond();
    uint256 liquidity = _liquidity(exit10.positionId0());
    uint64 startTime = uint64(block.timestamp);
    skip(1 days);
    uint64 endTime = uint64(block.timestamp);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    exit10.chickenOut(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    checkBondData(bondId, liquidity, 0, startTime, endTime, uint8(IExit10.BondStatus.chickenedOut));
    assertTrue(_liquidity(exit10.positionId0()) == 0, 'Check liquidity');
    checkTreasury(0, 0, 0, 0);
    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');
    checkBalances(address(exit10), 0, 0);
  }

  function testChickenOutNoBondsRevert() public {
    uint256 bondId = _skipBootAndCreateBond();
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    vm.prank(address(0xdead));
    vm.expectRevert(bytes('EXIT10: Caller must own the bond'));
    exit10.chickenOut(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testChickenOutActiveStatusRevert() public {
    uint256 bondId = _skipBootAndCreateBond();
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.chickenOut(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.chickenOut(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testChickenIn() public {
    uint256 bondId = _skipBootAndCreateBond();
    uint64 startTime = uint64(block.timestamp);
    uint256 liquidity = _liquidity(exit10.positionId0());
    skip(_accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.chickenIn(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint64 endTime = uint64(block.timestamp);
    checkBondData(bondId, liquidity, liquidity / 2, startTime, endTime, uint8(IExit10.BondStatus.chickenedIn));
    assertTrue(_liquidity(exit10.positionId0()) == 0, 'Check liquidity');
    uint256 exitBucket = _liquidity(exit10.positionId1()) - (liquidity / 2);
    checkTreasury(0, liquidity / 2, exitBucket, 0);
    checkBalances(address(exit10), 0, 0);
    assertTrue(exit10.BLP().balanceOf(address(this)) == (liquidity / 2) * exit10.TOKEN_MULTIPLIER());
    assertTrue(exit10.EXIT().balanceOf(address(this)) == exitBucket * exit10.TOKEN_MULTIPLIER(), 'Check exit bucket');
  }

  function testRedeem() public {
    uint256 bondId = _skipBootAndCreateBond();
    skip(_accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.chickenIn(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    uint128 liquidityToRemove = uint128(exit10.BLP().balanceOf(address(this)) / exit10.TOKEN_MULTIPLIER());
    exit10.redeem(
      IExit10.RemoveLiquidity({ liquidity: liquidityToRemove, amount0Min: 0, amount1Min: 0, deadline: block.timestamp })
    );
    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');
    checkBalances(address(exit10), 0, 0);
    assertTrue(exit10.BLP().balanceOf(address(this)) == 0, 'Check balance BLP');
    checkTreasury(0, 0, _liquidity(exit10.positionId1()), 0);
  }

  function testClaimAndDistributeFees() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    exit10.createBond(
      IExit10.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10_000_000_000000,
        amount1Desired: 10_000 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    _generateFees();
    exit10.claimAndDistributeFees();
    uint256 m0t0 = token0.balanceOf(_masterchef0);
    uint256 m0t1 = token1.balanceOf(_masterchef0);
    uint256 m1t0 = token0.balanceOf(_masterchef1);
    uint256 m1t1 = token1.balanceOf(_masterchef1);
    assertTrue(m0t0 > 0, 'Check masterchef0 balance token0');
    assertTrue(m0t1 > 0, 'Check masterchef0 balance token1');
    assertTrue(m1t0 > 0, 'Check masterchef1 balance token0');
    assertTrue(m1t1 > 0, 'Check masterchef1 balance token1');
    uint256 totalBalance0 = m0t0 + m1t0;
    uint256 totalBalance1 = m0t1 + m1t1;
    assertTrue(m0t0 == (totalBalance0 / 10) * 4, 'Check masterchef0 balance token0');
    assertTrue(m0t1 == (totalBalance1 / 10) * 4, 'Check masterchef0 balance token1');
    checkBalances(address(exit10), 0, 0);
  }

  function testExit10Revert() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Current Tick not below TICK_LOWER'));
    exit10.exit10();
  }

  function testExit10() public {
    exit10.bootstrapLock(
      IExit10.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint256 bondId = _skipBootAndCreateBond();
    skip(_accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.chickenIn(
      bondId,
      IExit10.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getTreasury();
    checkBalances(address(exit10), 0, 0);
    _eth10k();
    uint128 totalLiquidity = _liquidity(exit10.positionId1());
    exit10.exit10();
    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertTrue(_liquidity(exit10.positionId1()) == reserve, 'Check reserve amount');
    assertTrue(token0.balanceOf(address(exit10)) != 0, 'Check acquired USD != 0');
    uint256 AcquiredUSD = token0.balanceOf(address(exit10)) + token0.balanceOf(address(sto));
    uint256 exitLiquidityPlusBootstrap = totalLiquidity - reserve;
    assertTrue(exit + bootstrap == exitLiquidityPlusBootstrap, 'Check Exitbucket');
    uint256 exitBootstrapUSD = (bootstrap * AcquiredUSD) / exitLiquidityPlusBootstrap;
    uint256 exitLiquidityUSD = (AcquiredUSD - exitBootstrapUSD);
    uint256 share = exitLiquidityUSD / 10;
    assertTrue(exit10.exitBootstrap() == exitBootstrapUSD + share, 'Check Bootstrap USD share amount');
    assertTrue(exit10.exitTeamPlusBackers() == share * 2, 'Check team plus backers'); // 20%
    assertTrue(AcquiredUSD - (exitBootstrapUSD + share * 3) == exit10.exitLiquidity(), 'Check exit liquidity');
  }

  function testAccrualSchedule() public {
    uint256 bondId = _skipBootAndCreateBond();
    skip(_accrualParameter);
    assertTrue(exit10.getAccruedAmount(bondId) == _liquidity(exit10.positionId0()) / 2);
  }

  function _getTokensBalance() internal view returns (uint256 _token0, uint256 _token1) {
    _token0 = token0.balanceOf(address(this));
    _token1 = token1.balanceOf(address(this));
  }

  function _mintAndApprove(address _token, uint256 _amount) internal {
    deal(_token, address(this), _amount);
    _maxApprove(_token, address(exit10));
  }

  function _maxApprove(address _token, address _spender) internal {
    ERC20(_token).approve(_spender, MX);
  }

  function _skipBootAndCreateBond() internal returns (uint256 _bondId) {
    skip(exit10.BOOTSTRAP_PERIOD());
    _bondId = _createBond();
  }

  function _createBond() internal returns (uint256 _bondId) {
    _bondId = exit10.createBond(
      IExit10.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _generateFees() internal {
    uint256 amountOut = _swap(address(token0), address(token1), 100_000_000_000000);
    _swap(address(token1), address(token0), amountOut / 2);
  }

  function _eth10k() internal {
    _swap(address(token0), address(token1), 100_000_000_000000);
  }

  function _swap(
    address _in,
    address _out,
    uint256 _amount
  ) internal returns (uint256 _amountOut) {
    _amountOut = UNISWAP_ROUTER.exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: _in,
        tokenOut: _out,
        fee: 500,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: _amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );
  }

  function _liquidity(uint256 _positionId) internal view returns (uint128 _liq) {
    (, , , , , , , _liq, , , , ) = INPM(exit10.NPM()).positions(_positionId);
  }

  function _currentTick() internal view returns (int24 _tick) {
    (, _tick, , , , , ) = exit10.POOL().slot0();
  }

  function checkBalances(
    address holder,
    uint256 amount0,
    uint256 amount1
  ) internal {
    assertTrue(token0.balanceOf(holder) == amount0, 'Check balance 0');
    assertTrue(token1.balanceOf(holder) == amount1, 'Check balance 1');
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
