// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '../src/Exit10.sol';
import '../src/NFT.sol';
import '../src/STO.sol';
import '../src/interfaces/IExit10.sol';
import '../src/interfaces/IUniswapBase.sol';
import '../src/interfaces/IUniswapV3Router.sol';
import '../src/interfaces/INonfungiblePositionManager.sol';
import '../src/FeeSplitter.sol';

contract Exit10Test is Test {
  Exit10 exit10;
  NFT nft;
  STO sto;
  ERC20 token0;
  ERC20 token1;

  uint256 bootstrapPeriod = 1 hours;
  uint256 accrualParameter = 1 days;
  uint256 lpPerUSD = 1; // made up number

  uint256 initialBalance = 1_000_000_000 ether;
  uint256 deployTime;
  uint256 constant MX = type(uint256).max;

  IUniswapV3Router UNISWAP_ROUTER = IUniswapV3Router(vm.envAddress('UNISWAP_V3_ROUTER'));
  address feeSplitter;
  address masterchef0 = address(0x0a);
  address masterchef1 = address(0x0b);
  address masterchef2 = address(0x0c);

  IUniswapBase.BaseDeployParams baseParams =
    IUniswapBase.BaseDeployParams({
      uniswapFactory: vm.envAddress('UNISWAP_V3_FACTORY'),
      nonfungiblePositionManager: vm.envAddress('UNISWAP_V3_NPM'),
      tokenIn: vm.envAddress('WETH'),
      tokenOut: vm.envAddress('USDC'),
      fee: uint24(vm.envUint('FEE')),
      tickLower: int24(vm.envInt('LOWER_TICK')),
      tickUpper: int24(vm.envInt('UPPER_TICK'))
    });

  function setUp() public {
    nft = new NFT('Bond Data', 'BND', 0);
    sto = new STO(bytes32('merkle_root'));
    feeSplitter = address(new FeeSplitter(masterchef0, masterchef1));

    IExit10.DeployParams memory params = IExit10.DeployParams({
      NFT: address(nft),
      STO: address(sto),
      masterchef: masterchef2,
      feeSplitter: feeSplitter,
      bootstrapPeriod: bootstrapPeriod,
      accrualParameter: accrualParameter,
      lpPerUSD: lpPerUSD
    });

    exit10 = new Exit10(baseParams, params);
    sto.setExit10(address(exit10));
    nft.setExit10(address(exit10));
    FeeSplitter(feeSplitter).transferOwnership(address(exit10));

    deployTime = block.timestamp;
    token0 = ERC20(exit10.POOL().token0());
    token1 = ERC20(exit10.POOL().token1());

    _mintAndApprove(address(token0), initialBalance);
    _mintAndApprove(address(token1), initialBalance);
    _maxApprove(address(token0), address(UNISWAP_ROUTER));
    _maxApprove(address(token1), address(UNISWAP_ROUTER));
  }

  function testSetup() public {
    assertTrue(exit10.positionId() == 0, 'Check positionId');
    assertTrue(exit10.countConvertBond() == 0, 'Check count convert bond');
    assertTrue(exit10.countCancelBond() == 0, 'Check count cancel bond');
    assertTrue(exit10.inExitMode() == false, 'Check inExitMode');
    assertTrue(token0.balanceOf(address(this)) == initialBalance);
    assertTrue(token1.balanceOf(address(this)) == initialBalance);
  }

  function testBootstrapLock() public {
    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(amountAdded0 == initialBalance - token0.balanceOf(address(this)), 'Check amountAdded0');
    assertTrue(amountAdded1 == initialBalance - token1.balanceOf(address(this)), 'Check amountAdded1');
    assertTrue(tokenId == exit10.positionId(), 'Check positionId');
    assertTrue(liquidityAdded != 0, 'Check liquidityAdded');
    assertTrue(
      ERC20(exit10.BOOT()).balanceOf(address(this)) == liquidityAdded * exit10.TOKEN_MULTIPLIER(),
      'Check BOOT balance'
    );

    checkBalances(address(exit10), 0, 0);
    checkTreasury(0, 0, 0, liquidityAdded);
  }

  function testBootstrapRevert() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    vm.expectRevert(bytes('EXIT10: Bootstrap ended'));
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
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
      IUniswapBase.AddLiquidity({
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
      _liquidity(exit10.positionId()),
      0,
      uint64(block.timestamp),
      0,
      uint8(IExit10.BondStatus.active)
    );
    assertTrue(_liquidity(exit10.positionId()) != 0, 'Check liquidity');
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');

    checkBalances(address(exit10), 0, 0);
    checkTreasury(uint256(_liquidity(exit10.positionId())), 0, 0, 0);
  }

  function testCreateBondOnBehalfOfUser() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = exit10.createBond(
      IUniswapBase.AddLiquidity({
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

  function testCreateBondWithBootstrap() public {
    (, uint128 liquidityAdded, , ) = exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    skip(exit10.BOOTSTRAP_PERIOD());
    uint256 bondId = _createBond();
    checkBondData(
      bondId,
      _liquidity(exit10.positionId()) - liquidityAdded,
      0,
      uint64(block.timestamp),
      0,
      uint8(IExit10.BondStatus.active)
    );
    assertTrue(_liquidity(exit10.positionId()) != 0, 'Check liquidity');
    assertTrue(nft.ownerOf(bondId) == address(this), 'Check NFT owner');

    checkBalances(address(exit10), 0, 0);
    checkTreasury(uint256(_liquidity(exit10.positionId())) - liquidityAdded, 0, 0, liquidityAdded);
  }

  function testCancelBond() public {
    uint256 bondId = _skipBootAndCreateBond();
    uint256 liquidity = _liquidity(exit10.positionId());
    uint64 startTime = uint64(block.timestamp);
    skip(1 days);
    uint64 endTime = uint64(block.timestamp);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    assertTrue(_liquidity(exit10.positionId()) == 0, 'Check liquidity');
    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');
    assertTrue(exit10.countCancelBond() == 1, 'Check bond count');

    checkBalances(address(exit10), 0, 0);
    checkBondData(bondId, liquidity, 0, startTime, endTime, uint8(IExit10.BondStatus.cancelled));
    checkTreasury(0, 0, 0, 0);
  }

  function testCancelBondNoBondsRevert() public {
    uint256 bondId = _skipBootAndCreateBond();
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    vm.prank(address(0xdead));
    vm.expectRevert(bytes('EXIT10: Caller must own the bond'));
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testCancelBondActiveStatusRevert() public {
    uint256 bondId = _skipBootAndCreateBond();
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.expectRevert(bytes('EXIT10: Bond must be active'));
    exit10.cancelBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function testConvertBond() public {
    uint256 bondId = _skipBootAndCreateBond();
    uint64 startTime = uint64(block.timestamp);
    uint256 liquidity = _liquidity(exit10.positionId());

    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    uint64 endTime = uint64(block.timestamp);
    uint256 exitBucket = _liquidity(exit10.positionId()) - (liquidity / 2);

    assertTrue(exit10.BLP().balanceOf(address(this)) == (liquidity / 2) * exit10.TOKEN_MULTIPLIER());
    assertTrue(exit10.EXIT().balanceOf(address(this)) == exitBucket * exit10.TOKEN_MULTIPLIER(), 'Check exit bucket');

    checkBalances(address(exit10), 0, 0);
    checkBondData(bondId, liquidity, liquidity / 2, startTime, endTime, uint8(IExit10.BondStatus.converted));
    checkTreasury(0, liquidity / 2, exitBucket, 0);
  }

  function testRedeem() public {
    uint256 bondId = _skipBootAndCreateBond();
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 balanceToken0, uint256 balanceToken1) = _getTokensBalance();
    uint128 liquidityToRemove = uint128(exit10.BLP().balanceOf(address(this)) / exit10.TOKEN_MULTIPLIER());
    exit10.redeem(
      IUniswapBase.RemoveLiquidity({
        liquidity: liquidityToRemove,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertTrue(token0.balanceOf(address(this)) > balanceToken0, 'Check balance token0');
    assertTrue(token1.balanceOf(address(this)) > balanceToken1, 'Check balance token1');
    assertTrue(exit10.BLP().balanceOf(address(this)) == 0, 'Check balance BLP');

    checkBalances(address(exit10), 0, 0);
    checkTreasury(0, 0, _liquidity(exit10.positionId()), 0);
  }

  function testClaimAndDistributeFees() public {
    skip(exit10.BOOTSTRAP_PERIOD());
    exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10_000_000_000000,
        amount1Desired: 10_000 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    _generateFees();

    checkTreasury(_liquidity(exit10.positionId()), 0, 0, 0);

    exit10.claimAndDistributeFees();
    uint256 feesClaimed0 = token0.balanceOf(feeSplitter);
    uint256 feesClaimed1 = token1.balanceOf(feeSplitter);

    assertTrue(feesClaimed0 != 0, 'Check fees claimed 0');
    assertTrue(feesClaimed1 != 0, 'Check fees claimed 1');

    checkBalances(address(exit10), 0, 0);
  }

  function testExit10Revert() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Current Tick not below TICK_LOWER'));
    exit10.exit10();
  }

  function testExit10() public {
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint256 bondId = _skipBootAndCreateBond();
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) = exit10.getTreasury();
    checkBalances(address(exit10), 0, 0);

    _eth10k();
    uint128 totalLiquidity = _liquidity(exit10.positionId());
    exit10.exit10();

    assertTrue(exit10.inExitMode(), 'Check inExitMode');
    assertTrue(_liquidity(exit10.positionId()) - pending == reserve, 'Check reserve amount');
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
    assertTrue(ERC20(token1).balanceOf(address(exit10)) == 0, 'Check balance token1 == 0');
  }

  function testBootstrapClaim() public {
    exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: 10000_000000,
        amount1Desired: 10 ether,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    uint256 bondId = _skipBootAndCreateBond();
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    _eth10k();
    exit10.exit10();
    (uint256 pending, uint256 reserve, , uint256 bootstrap) = exit10.getTreasury();

    assertTrue(_liquidity(exit10.positionId()) == pending + reserve, 'Check liquidity position');

    uint256 currentBalanceUSDC = ERC20(token0).balanceOf(address(this));
    uint256 bootBalance = ERC20(exit10.BOOT()).balanceOf(address(this));
    exit10.bootstrapClaim();
    uint256 claimableAmount = ((bootBalance / exit10.TOKEN_MULTIPLIER()) * exit10.exitBootstrap()) / bootstrap;

    assertTrue(ERC20(exit10.BOOT()).balanceOf(address(this)) == 0, 'Check BOOT burned');
    assertTrue(
      ERC20(token0).balanceOf(address(this)) - currentBalanceUSDC == claimableAmount,
      'Check claimable amount'
    );
    assertTrue(ERC20(token0).balanceOf(address(this)) == currentBalanceUSDC + claimableAmount, 'Check amount claimed');
    assertTrue(claimableAmount != 0, 'Check claimable != 0');
  }

  function testBootstrapClaimRevert() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.bootstrapClaim();
  }

  function testExitClaim() public {
    uint256 bondId = _skipBootAndCreateBond();
    skip(accrualParameter);
    (uint256 bondAmount, , , , ) = exit10.getBondData(bondId);
    exit10.convertBond(
      bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );

    assertTrue(ERC20(exit10.EXIT()).balanceOf(address(this)) != 0, 'Check exit balance');

    _eth10k();
    exit10.exit10();
    uint256 currentBalanceUSDC = ERC20(token0).balanceOf(address(this));
    exit10.exitClaim();

    assertTrue(ERC20(exit10.EXIT()).balanceOf(address(this)) == 0, 'Check exit burn');
    assertTrue(ERC20(token0).balanceOf(address(this)) == currentBalanceUSDC + exit10.exitLiquidity());
  }

  function testExitClaimRevert() public {
    _skipBootAndCreateBond();
    vm.expectRevert(bytes('EXIT10: Not in Exit mode'));
    exit10.exitClaim();
  }

  function testAccrualSchedule() public {
    uint256 bondId = _skipBootAndCreateBond();
    skip(accrualParameter);
    assertTrue(exit10.getAccruedAmount(bondId) == _liquidity(exit10.positionId()) / 2);
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
      IUniswapBase.AddLiquidity({
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
    _swap(address(token0), address(token1), 200_000_000_000000);
  }

  function _swap(
    address _in,
    address _out,
    uint256 _amount
  ) internal returns (uint256 _amountOut) {
    _amountOut = UNISWAP_ROUTER.exactInputSingle(
      IUniswapV3Router.ExactInputSingleParams({
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
