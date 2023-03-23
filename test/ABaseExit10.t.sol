// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { UniswapBase } from '../src/UniswapBase.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseTest } from './ABase.t.sol';
import { BaseToken } from '../src/BaseToken.sol';
import { STOToken } from '../src/STOToken.sol';
import { NFT } from '../src/NFT.sol';
import { FeeSplitter } from '../src/FeeSplitter.sol';
import { MasterchefExit } from '../src/Exit10.sol';
import { Masterchef } from '../src/Masterchef.sol';
import { Exit10 } from '../src/Exit10.sol';

abstract contract ABaseExit10Test is Test, ABaseTest {
  Exit10 exit10;
  NFT nft;
  STOToken sto;
  BaseToken boot;
  BaseToken blp;
  BaseToken exit;

  // On Ethereum Mainnet:
  // Token0 is USDC
  // Token1 is WETH
  ERC20 token0;
  ERC20 token1;

  address weth = vm.envAddress('WETH');
  address usdc = vm.envAddress('USDC');
  address feeSplitter;
  address lp; // EXIT/USDC LP Uniswap v2

  uint256 initialBalance = 1_000_000_000 ether;
  uint256 bootstrapPeriod = 2 weeks;
  uint256 accrualParameter = 1 weeks;
  uint256 bootstrapTarget = vm.envUint('BOOTSTRAP_TARGET');
  uint256 bootstrapCap = vm.envUint('BOOTSTRAP_CAP');
  uint256 liquidityPerUsd = vm.envUint('LIQUIDITY_PER_USDC');
  uint256 exitDiscount = vm.envUint('EXIT_DISCOUNT');
  uint256 deployTime;

  Masterchef masterchef0; // 50% BOOT 50% STO
  Masterchef masterchef1; // BLP
  MasterchefExit masterchefExit; // EXIT/USDC LP Uniswap v2

  uint256 constant ORACLE_SECONDS = 60;
  uint256 constant REWARDS_DURATION = 2 weeks;

  UniswapBase.BaseDeployParams baseParams =
    UniswapBase.BaseDeployParams({
      weth: weth,
      uniswapFactory: vm.envAddress('UNISWAP_V3_FACTORY'),
      nonfungiblePositionManager: vm.envAddress('UNISWAP_V3_NPM'),
      tokenIn: weth,
      tokenOut: usdc,
      fee: uint24(vm.envUint('FEE')),
      tickLower: int24(vm.envInt('LOWER_TICK')),
      tickUpper: int24(vm.envInt('UPPER_TICK'))
    });

  function setUp() public virtual {
    deployTime = block.timestamp;
    // Deploy tokens
    sto = new STOToken(bytes32('merkle_root'));
    boot = new BaseToken('Bootstap', 'BOOT');
    blp = new BaseToken('Boost LP', 'BLP');
    exit = new BaseToken('Exit Liquidity', 'EXIT');
    nft = new NFT('Bond Data', 'BND', 0);

    // Deploy dependency contracts
    masterchef0 = new Masterchef(weth, REWARDS_DURATION);
    masterchef1 = new Masterchef(weth, REWARDS_DURATION);
    masterchefExit = new MasterchefExit(address(exit), REWARDS_DURATION);

    feeSplitter = address(new FeeSplitter(address(masterchef0), address(masterchef1), vm.envAddress('SWAPPER')));
    Exit10.DeployParams memory params = Exit10.DeployParams({
      NFT: address(nft),
      STO: address(sto),
      BOOT: address(boot),
      BLP: address(blp),
      EXIT: address(exit),
      masterchef: address(masterchefExit),
      feeSplitter: feeSplitter,
      bootstrapPeriod: bootstrapPeriod,
      bootstrapTarget: bootstrapTarget,
      bootstrapCap: bootstrapCap,
      accrualParameter: accrualParameter,
      liquidityPerUsd: liquidityPerUsd,
      exitDiscount: exitDiscount
    });

    exit10 = new Exit10(baseParams, params);
    nft.setExit10(address(exit10));
    FeeSplitter(feeSplitter).setExit10(address(exit10));
    exit.mint(address(this), 1000 ether);
    lp = _setUpExitLiquidity(usdc, address(exit), 10, 10);
    _setUpExitPool(exit10, lp);
    _setMasterchefs(feeSplitter);

    boot.transferOwnership(address(exit10));
    blp.transferOwnership(address(exit10));
    exit.transferOwnership(address(exit10));

    token0 = ERC20(exit10.POOL().token0());
    token1 = ERC20(exit10.POOL().token1());

    _maxApprove(weth, usdc, address(UNISWAP_V3_ROUTER));
    _mintAndApprove(address(token0), initialBalance, address(exit10));
    _mintAndApprove(address(token1), initialBalance, address(exit10));
  }

  function _setMasterchefs(address _rewardDistributor) internal {
    masterchef0.add(50, address(sto));
    masterchef0.add(50, address(boot));
    masterchef1.add(100, address(blp));
    masterchef0.setRewardDistributor(_rewardDistributor);
    masterchef1.setRewardDistributor(_rewardDistributor);
    masterchef0.renounceOwnership();
    masterchef1.renounceOwnership();
  }

  function _skipBootAndCreateBond() internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    _skipBootstrap();
    (_bondId, _liquidityAdded) = _createBond();
  }

  function _createBond(uint256 _amount0, uint256 _amount1) internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    (_bondId, _liquidityAdded, , ) = exit10.createBond(_addLiquidityParams(_amount0, _amount1));
  }

  function _createBond() internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    return _createBond(10000_000000, 10 ether);
  }

  function _skipBootstrap() internal {
    skip(exit10.BOOTSTRAP_PERIOD());
  }

  function _skipToExit() internal {
    exit10.bootstrapLock(_addLiquidityParams(10000_000000, 10 ether));
    _skipBootstrap();
    _eth10k();
    exit10.exit10();
  }

  function _skipToExitWithBond() internal returns (uint256) {
    _skipBootstrap();
    (uint256 bondId, ) = _createBond();
    _eth10k();
    exit10.exit10();
    return bondId;
  }

  function _setUpExitPool(Exit10 _exit10, address _lp) internal {
    MasterchefExit(_exit10.MASTERCHEF()).add(100, _lp);
    _exit10.EXIT().mint(_exit10.MASTERCHEF(), _exit10.LP_EXIT_REWARD());
    MasterchefExit(_exit10.MASTERCHEF()).updateRewards(_exit10.LP_EXIT_REWARD());
    MasterchefExit(_exit10.MASTERCHEF()).transferOwnership(address(_exit10));
  }

  function _setUpExitLiquidity(
    address _token0,
    address _token1,
    uint256 _amountNoDecimal0,
    uint256 _amountNoDecimal1
  ) internal returns (address pair) {
    uint amount0 = _tokenAmount(_token0, _amountNoDecimal0);
    uint amount1 = _tokenAmount(_token1, _amountNoDecimal1);
    deal(_token0, address(this), amount0);
    deal(_token1, address(this), amount1);
    pair = UNISWAP_V2_FACTORY.createPair(_token0, _token1);
    _addLiquidity(_token0, _token1, amount0, amount1);
  }

  function _addLiquidity(
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1
  ) internal returns (uint _amount0Added, uint _amount1Added, uint _liquidityAmount) {
    ERC20(_token0).approve(address(UNISWAP_V2_ROUTER), _amount0);
    ERC20(_token1).approve(address(UNISWAP_V2_ROUTER), _amount1);
    (_amount0Added, _amount1Added, _liquidityAmount) = UNISWAP_V2_ROUTER.addLiquidity(
      _token0,
      _token1,
      _amount0,
      _amount1,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _liquidity(uint256 _positionId, Exit10 _exit10) internal view returns (uint128 _liq) {
    (, , , , , , , _liq, , , , ) = INPM(_exit10.NPM()).positions(_positionId);
  }

  function __liquidity() internal view returns (uint128 _liq) {
    (, , , , , , , _liq, , , , ) = INPM(exit10.NPM()).positions(exit10.positionId());
  }

  function _currentTick(Exit10 _exit10) internal view returns (int24 _tick) {
    (, _tick, , , , , ) = _exit10.POOL().slot0();
  }

  function _eth10k() internal {
    _swap(exit10.TOKEN_OUT(), exit10.TOKEN_IN(), 200_000_000_000000);
  }

  function _checkBuckets(uint256 _pending, uint256 _reserve, uint256 _exit, uint256 _bootstrap) internal {
    (uint256 statePending, uint256 stateReserve, uint256 stateExit, uint256 stateBootstrap) = exit10.getBuckets();
    assertEq(statePending, _pending, 'Treasury: Pending bucket check');
    assertEq(stateReserve, _reserve, 'Treasury: Reserve bucket check');
    assertEq(stateExit, _exit, 'Treasury: Exit bucket check');
    assertEq(stateBootstrap, _bootstrap, 'Treasury: Bootstrap bucket check');
  }

  function _checkBondData(
    uint256 _bondId,
    uint256 _bondAmount,
    uint256 _claimedBoostAmount,
    uint256 _startTime,
    uint256 _endTime,
    uint8 _status
  ) internal {
    (uint256 bondAmount, uint256 claimedBoostToken, uint64 startTime, uint64 endTime, uint8 status) = exit10
      .getBondData(_bondId);
    assertTrue(bondAmount == _bondAmount, 'Check bond amount');
    assertTrue(claimedBoostToken == _claimedBoostAmount, 'Check claimed boosted tokens');
    assertTrue(startTime == uint64(_startTime), 'Check startTime');
    assertTrue(endTime == uint64(_endTime), 'Check endTime');
    assertTrue(status == _status, 'Check status');
  }

  function _addLiquidityParams(
    uint256 _amount0,
    uint256 _amount1
  ) internal view returns (UniswapBase.AddLiquidity memory) {
    return
      UniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: _amount0,
        amount1Desired: _amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      });
  }

  function _addLiquidityParams(
    address _depositor,
    uint256 _amount0,
    uint256 _amount1
  ) internal view returns (UniswapBase.AddLiquidity memory) {
    return
      UniswapBase.AddLiquidity({
        depositor: _depositor,
        amount0Desired: _amount0,
        amount1Desired: _amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      });
  }

  function _removeLiquidityParams(uint256 _liq) internal view returns (UniswapBase.RemoveLiquidity memory) {
    return
      UniswapBase.RemoveLiquidity({
        liquidity: uint128(_liq),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      });
  }

  function _checkBalancesExit10(uint256 _amount0, uint256 _amount1) internal {
    assertTrue(ERC20(token0).balanceOf(address(exit10)) == _amount0, 'Check balance 0');
    assertTrue(ERC20(token1).balanceOf(address(exit10)) == _amount1, 'Check balance 1');
  }

  function _checkBalances(uint256 _amount0, uint256 _amount1) internal {
    assertEq(_balance0(), _amount0, 'Check balance 0');
    assertEq(_balance1(), _amount1, 'Check balance 1');
  }

  function _getTokensBalance() internal view returns (uint256 _balance0, uint256 _balance1) {
    (_balance0, _balance1) = _getTokensBalance(token0, token1);
  }

  function _balance0() internal view returns (uint256) {
    return _balance(token0);
  }

  function _balance1() internal view returns (uint256) {
    return _balance(token1);
  }
}
