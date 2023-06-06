// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { UniswapBase } from '../src/UniswapBase.sol';
import { INPM } from '../src/interfaces/INonfungiblePositionManager.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { ABaseTest } from './ABase.t.sol';
import { BaseToken } from '../src/BaseToken.sol';
import { STOToken } from '../src/STOToken.sol';
import { NFT } from '../src/NFT.sol';
import { Artwork } from '../src/artwork/Artwork.sol';
import { FeeSplitter } from '../src/FeeSplitter.sol';
import { MasterchefExit } from '../src/Exit10.sol';
import { Masterchef } from '../src/Masterchef.sol';
import { Exit10 } from '../src/Exit10.sol';
import { MockLido } from '../src/mocks/MockLido.sol';

abstract contract ABaseExit10Test is ABaseTest {
  Exit10 exit10;
  address artwork;
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

  address feeSplitter;
  address lp; // EXIT/USDC LP Uniswap v2

  uint256 initialBalance = 1_000_000_000 ether;
  uint256 deployTime;
  uint256 defaultValue = 100;
  uint256 amount0;
  uint256 amount1;

  address lido;
  address weth = vm.envAddress('WETH');
  address usdc = vm.envAddress('USDC');
  address beneficiary = vm.envAddress('BENEFICIARY');
  address uniswapV3Factory = vm.envAddress('UNISWAP_V3_FACTORY');
  address nonfungiblePositionManager = vm.envAddress('UNISWAP_V3_NPM');
  uint256 accrualParameter = vm.envUint('ACCRUAL_PARAMETER');
  uint256 bootstrapStart = vm.envUint('BOOTSTRAP_START');
  uint256 bootstrapDuration = vm.envUint('BOOTSTRAP_DURATION');
  uint256 liquidityPerUsd = vm.envUint('LIQUIDITY_PER_USDC');
  uint256 bootstrapCap = vm.envUint('BOOTSTRAP_LIQUIDITY_CAP');
  uint24 fee = uint24(vm.envUint('FEE'));
  int24 tickLower = int24(vm.envInt('LOWER_TICK'));
  int24 tickUpper = int24(vm.envInt('UPPER_TICK'));
  uint256 rewardsDuration = vm.envUint('REWARDS_DURATION');
  uint256 rewardsDurationExit = vm.envUint('REWARDS_DURATION_EXIT');
  uint256 nftLockPeriod = vm.envUint('TRANSFER_LOCKOUT_PERIOD_SECONDS');

  uint256 constant DECIMAL_PRECISION = 1e18;
  uint256 constant USDC_DECIMALS = 1e6;
  uint256 constant ORACLE_SECONDS = 60;

  Masterchef masterchef; // 50% BOOT 50% STO
  MasterchefExit masterchefExit; // EXIT/USDC LP Uniswap v2 20% | BLP 80%

  UniswapBase.BaseDeployParams baseParams =
    UniswapBase.BaseDeployParams({
      weth: weth,
      uniswapFactory: uniswapV3Factory,
      nonfungiblePositionManager: nonfungiblePositionManager,
      tokenIn: weth,
      tokenOut: usdc,
      fee: fee,
      tickLower: tickLower,
      tickUpper: tickUpper
    });

  function setUp() public virtual {
    lido = address(new MockLido());

    deployTime = block.timestamp;
    // Deploy tokens
    sto = new STOToken(bytes32('merkle_root'));
    boot = new BaseToken('Bootstap', 'BOOT');
    blp = new BaseToken('Base LP', 'BLP');
    exit = new BaseToken('Exit Liquidity', 'EXIT');
    nft = new NFT('Bond Data', 'BND', nftLockPeriod);

    // Deploy dependency contracts
    masterchef = new Masterchef(weth, rewardsDuration);
    masterchefExit = new MasterchefExit(address(exit), rewardsDurationExit);

    bootstrapStart = block.timestamp;

    feeSplitter = address(new FeeSplitter(address(masterchef), vm.envAddress('SWAPPER')));
    Exit10.DeployParams memory params = Exit10.DeployParams({
      NFT: address(nft),
      STO: address(sto),
      BOOT: address(boot),
      BLP: address(blp),
      EXIT: address(exit),
      masterchef: address(masterchefExit),
      feeSplitter: feeSplitter,
      beneficiary: beneficiary,
      lido: _getLidoAddress(),
      bootstrapStart: bootstrapStart,
      bootstrapDuration: bootstrapDuration,
      bootstrapCap: _getBootstrapCap(),
      accrualParameter: accrualParameter,
      liquidityPerUsd: liquidityPerUsd
    });

    exit10 = new Exit10(baseParams, params);
    artwork = address(new Artwork(payable(exit10)));
    nft.setExit10(payable(exit10));
    nft.setArtwork(artwork);
    FeeSplitter(feeSplitter).setExit10(payable(exit10));
    lp = _pairForUniswapV2(address(UNISWAP_V2_FACTORY), usdc, address(exit));
    _setMasterchef(feeSplitter);
    _setMasterchefExit(exit10, lp, address(blp));

    boot.transferOwnership(address(exit10));
    sto.transferOwnership(address(exit10));
    blp.transferOwnership(address(exit10));
    exit.transferOwnership(address(exit10));

    token0 = ERC20(exit10.POOL().token0());
    token1 = ERC20(exit10.POOL().token1());

    amount0 = _tokenAmount(address(token0), defaultValue);
    amount1 = _Convert0ToToken1(amount0);

    _maxApprove(weth, usdc, address(UNISWAP_V3_ROUTER));
    _mintAndApprove(address(token0), initialBalance, address(exit10));
    _mintAndApprove(address(token1), initialBalance, address(exit10));

    _mintAndApprove(alice, address(token0), initialBalance, address(exit10));
    _mintAndApprove(alice, address(token1), initialBalance, address(exit10));
  }

  function _setMasterchef(address _rewardDistributor) internal {
    masterchef.add(50, address(sto));
    masterchef.add(50, address(boot));
    masterchef.transferOwnership(_rewardDistributor);
  }

  function _setMasterchefExit(Exit10 _exit10, address _lp, address _blp) internal {
    MasterchefExit(_exit10.MASTERCHEF()).add(20, _lp);
    MasterchefExit(_exit10.MASTERCHEF()).add(80, _blp);
    MasterchefExit(_exit10.MASTERCHEF()).transferOwnership(address(_exit10));
  }

  function _bootstrapLock(
    uint256 _amount0,
    uint256 _amount1
  ) internal returns (uint256 _liquidityAdded, uint256 _amountAdded0, uint256 _amountAdded1) {
    (, _liquidityAdded, _amountAdded0, _amountAdded1) = exit10.bootstrapLock(
      UniswapBase.AddLiquidity({
        depositor: address(this),
        amount0Desired: _amount0,
        amount1Desired: _amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
  }

  function _skipBootAndCreateBond(
    uint256 _bootstrapDeposit0,
    uint256 _bootstrapDeposit1,
    uint256 _bondDeposit0,
    uint256 _bondDeposit1
  ) internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    exit10.bootstrapLock(_addLiquidityParams(_bootstrapDeposit0, _bootstrapDeposit1));
    _skipBootstrap();
    (_bondId, _liquidityAdded) = _createBond(_bondDeposit0, _bondDeposit1);
  }

  function _skipBootAndCreateBond(
    uint256 _bondDeposit0,
    uint256 _bondDeposit1
  ) internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    _skipBootstrap();
    (_bondId, _liquidityAdded) = _createBond(_bondDeposit0, _bondDeposit1);
  }

  function _skipBootAndCreateBond() internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    _skipBootstrap();
    (_bondId, _liquidityAdded) = _createBond();
  }

  function _createBond(uint256 _amount0, uint256 _amount1) internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    (_bondId, _liquidityAdded, , ) = exit10.createBond(_addLiquidityParams(_amount0, _amount1));
  }

  function _createBond() internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    return _createBond(amount0, amount1);
  }

  function _createBond(address _as) internal returns (uint256 _bondId, uint128 _liquidityAdded) {
    (_bondId, _liquidityAdded, , ) = exit10.createBond(_addLiquidityParams(_as, amount0, amount1));
  }

  function _skipBootstrap() internal {
    skip(bootstrapDuration);
  }

  function _skipToExit() internal {
    exit10.bootstrapLock(_addLiquidityParams(amount0, amount1));
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

  function _getLiquidity() internal view returns (uint128 _liq) {
    (, , , , , , , _liq, , , , ) = INPM(exit10.NPM()).positions(exit10.positionId());
  }

  function _currentTick(Exit10 _exit10) internal view returns (int24 _tick) {
    (, _tick, , , , , ) = _exit10.POOL().slot0();
  }

  function _eth10k() internal {
    // tokenOut == USDC
    // tokenIN == WETH

    address tokenOut = exit10.TOKEN_OUT();
    address tokenIn = exit10.TOKEN_IN();
    uint256 amount = _tokenAmount(tokenOut, 200_000_000);

    if (tokenOut < tokenIn) {
      do {
        deal(tokenOut, address(this), amount);
        _swap(tokenOut, tokenIn, amount);
      } while (_currentTick(exit10) >= tickLower);
    } else if (tokenIn < tokenOut) {
      do {
        deal(tokenOut, address(this), amount);
        _swap(tokenOut, tokenIn, amount);
      } while (_currentTick(exit10) <= tickUpper);
    }

    // We need to skip at least one second in order to make sure
    // we are able to pass the OracleLibrary.getBlockStartingTickAndLiquidity() check
    skip(1);
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
    uint256 _claimedBLP,
    uint256 _startTime,
    uint256 _endTime,
    uint8 _status
  ) internal {
    (uint256 bondAmount, uint256 claimedBLP, uint64 startTime, uint64 endTime, uint8 status) = exit10.getBondData(
      _bondId
    );
    assertEq(bondAmount, _bondAmount, 'Check bond amount');
    assertEq(claimedBLP, _claimedBLP, 'Check bond claimed blp tokens');
    assertEq(startTime, uint64(_startTime), 'Check bond startTime');
    assertEq(endTime, uint64(_endTime), 'Check bond endTime');
    assertEq(status, _status, 'Check bond status');
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
    assertEq(ERC20(token0).balanceOf(address(exit10)), _amount0, 'Check balance exit10, token0');
    assertEq(ERC20(token1).balanceOf(address(exit10)), _amount1, 'Check balance exit10, token1');
  }

  function _checkBalances(uint256 _amount0, uint256 _amount1) internal {
    assertEq(_balance0(), _amount0, 'Check my balance token0');
    assertEq(_balance1(), _amount1, 'Check my balance token1');
  }

  function _getTokensBalance() internal view returns (uint256 _bal0, uint256 _bal1) {
    (_bal0, _bal1) = _getTokensBalance(token0, token1);
  }

  function _balance0() internal view returns (uint256) {
    return _balance(token0);
  }

  function _balance1() internal view returns (uint256) {
    return _balance(token1);
  }

  function _getExitAmount(uint256 _liquidity) internal view virtual returns (uint256) {
    return (_liquidity * DECIMAL_PRECISION) / liquidityPerUsd / 100;
  }

  function _getTotalDepositedUSD(uint256 _amount0, uint256 _amount1) internal view returns (uint256) {
    uint256 wethAmountInUSD = (_amount1 * _returnPriceInUSD()) / DECIMAL_PRECISION;
    return wethAmountInUSD + _amount0;
  }

  function _returnPriceInUSD() internal view returns (uint256) {
    uint160 sqrtPriceX96;
    (sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    uint256 a = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 10 ** ERC20(exit10.POOL().token0()).decimals();
    uint256 b = 1 << 192;
    uint256 uintPrice = a / b;
    if (exit10.TOKEN_OUT() < exit10.TOKEN_IN()) {
      return (1 ether * 1e6) / uintPrice;
    } else {
      return uintPrice;
    }
  }

  function _getBootstrapCap() internal view virtual returns (uint256) {
    return vm.envUint('BOOTSTRAP_LIQUIDITY_CAP');
  }

  function _getLidoAddress() internal view virtual returns (address) {
    return lido;
  }

  function _Convert0ToToken1(uint256 _amount0) internal view returns (uint256) {
    (uint160 sqrtPriceX96, , , , , , ) = exit10.POOL().slot0();
    return convert0ToToken1(sqrtPriceX96, _amount0, token0.decimals());
  }
}
