// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { IUniswapBase } from '../src/interfaces/IUniswapBase.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseTest } from './ABase.t.sol';
import { BaseToken } from '../src/BaseToken.sol';
import { STO } from '../src/STO.sol';
import { NFT } from '../src/NFT.sol';
import { FeeSplitter } from '../src/FeeSplitter.sol';
import { MasterchefExit } from '../src/Exit10.sol';
import { Masterchef } from '../src/Masterchef.sol';
import { Exit10, IExit10 } from '../src/Exit10.sol';

abstract contract ABaseExit10Test is Test, ABaseTest {
  Exit10 exit10;
  NFT nft;
  STO sto;
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
  uint256 lpPerUSD = 1; // made up number
  uint256 deployTime;

  Masterchef masterchef0; // 50% BOOT 50% STO
  Masterchef masterchef1; // BLP
  MasterchefExit masterchef2; // EXIT/USDC LP Uniswap v2

  uint256 constant ORACLE_SECONDS = 60;
  uint256 constant REWARDS_DURATION = 2 weeks;

  IUniswapBase.BaseDeployParams baseParams =
    IUniswapBase.BaseDeployParams({
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
    sto = new STO(bytes32('merkle_root'));
    boot = new BaseToken('Bootstap', 'BOOT');
    blp = new BaseToken('Boost LP', 'BLP');
    exit = new BaseToken('Exit Liquidity', 'EXIT');
    nft = new NFT('Bond Data', 'BND', 0);

    // Deploy dependency contracts
    masterchef0 = new Masterchef(weth, REWARDS_DURATION);
    masterchef1 = new Masterchef(weth, REWARDS_DURATION);
    masterchef2 = new MasterchefExit(address(exit), REWARDS_DURATION);

    feeSplitter = address(new FeeSplitter(address(masterchef0), address(masterchef1), vm.envAddress('SWAPPER')));
    IExit10.DeployParams memory params = IExit10.DeployParams({
      NFT: address(nft),
      STO: address(sto),
      BOOT: address(boot),
      BLP: address(blp),
      EXIT: address(exit),
      masterchef: address(masterchef2),
      feeSplitter: feeSplitter,
      bootstrapPeriod: bootstrapPeriod,
      accrualParameter: accrualParameter,
      lpPerUSD: lpPerUSD
    });

    exit10 = new Exit10(baseParams, params);
    sto.setExit10(address(exit10));
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

    _maxApprove(weth, address(UNISWAP_V3_ROUTER));
    _maxApprove(usdc, address(UNISWAP_V3_ROUTER));
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
    (uint256 statePending, uint256 stateReserve, uint256 stateExit, uint256 stateBootstrap) = _exit10.getBuckets();
    assertTrue(statePending == _pending, 'Treasury: Pending bucket check');
    assertTrue(stateReserve == _reserve, 'Treasury: Reserve bucket check');
    assertTrue(stateExit == _exit, 'Treasury: Exit bucket check');
    assertTrue(stateBootstrap == _bootstrap, 'Treasury: Bootstrap bucket check');
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
