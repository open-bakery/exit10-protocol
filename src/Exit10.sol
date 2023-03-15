// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/IUniswapV3Pool.sol';
import './interfaces/INFT.sol';
import './interfaces/IExit10.sol';
import './utils/BaseMath.sol';
import './BaseToken.sol';
import './FeeSplitter.sol';
import './UniswapBase.sol';

import './MasterchefExit.sol';

import 'forge-std/Test.sol';

contract Exit10 is IExit10, BaseMath, UniswapBase {
  using SafeERC20 for ERC20;

  uint256 private pendingAmount;
  uint256 private reserveAmount;
  uint256 private bootstrapAmount;
  uint256 private finalExitAmount;

  // EXIT
  uint256 public exitTotalSupply;
  uint256 public exitLiquidity; // 70% of Exit Bucket
  uint256 public exitLiquidityClaimed;

  // BOOT
  uint256 public exitBootstrap;
  uint256 public exitBootstrapClaimed;

  // STO
  uint256 public exitTeamPlusBackers;

  bool public inExitMode;

  mapping(uint256 => BondData) private idToBondData;
  mapping(address => uint256) public bootstrapDeposit;

  // --- Constants ---
  uint256 private constant DEADLINE = 1e10;
  uint256 public constant TOKEN_MULTIPLIER = 1e8;
  uint256 public constant LP_EXIT_REWARD = 3_000_000 ether;
  uint256 public constant BONDERS_EXIT_REWARD = 7_000_000 ether;
  uint256 constant MAX_EXIT_SUPPLY = LP_EXIT_REWARD + BONDERS_EXIT_REWARD;
  uint256 constant MAX_UINT_256 = type(uint256).max;
  uint128 constant MAX_UINT_128 = type(uint128).max;

  // On Ethereum Mainnet:
  // Token0 is USDC
  // Token1 is WETH

  BaseToken public immutable EXIT;
  BaseToken public immutable BLP;
  BaseToken public immutable BOOT;
  INFT public immutable NFT;

  address public immutable MASTERCHEF; // EXIT/USDC Stakers
  address public immutable STO;
  address public immutable FEE_SPLITTER;

  uint256 public immutable DEPLOYMENT_TIMESTAMP;
  uint256 public immutable BOOTSTRAP_PERIOD;
  uint256 public immutable ACCRUAL_PARAMETER; // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.
  uint256 public immutable LP_PER_USD;

  // --- Events ---
  event CreateBond(address indexed bonder, uint256 bondID, uint256 amount);
  event CancelBond(address indexed bonder, uint256 bondID, uint256 amountReturned0, uint256 amountReturned1);
  event ConvertBond(
    address indexed bonder,
    uint256 bondID,
    uint256 bondAmount,
    uint256 boostTokenClaimed,
    uint256 exitLiquidityAmount
  );
  event Redeem(address indexed redeemer, uint256 amount0, uint256 amount1);
  event MintExit(address indexed recipient, uint256 amount);

  constructor(IUniswapBase.BaseDeployParams memory baseParams_, DeployParams memory params) UniswapBase(baseParams_) {
    DEPLOYMENT_TIMESTAMP = block.timestamp;

    STO = params.STO;
    NFT = INFT(params.NFT);

    BOOT = BaseToken(params.BOOT);
    BLP = BaseToken(params.BLP);
    EXIT = BaseToken(params.EXIT);

    MASTERCHEF = params.masterchef;
    FEE_SPLITTER = params.feeSplitter;

    BOOTSTRAP_PERIOD = params.bootstrapPeriod;
    ACCRUAL_PARAMETER = params.accrualParameter * DECIMAL_PRECISION;
    LP_PER_USD = params.lpPerUSD;

    ERC20(IUniswapV3Pool(POOL).token0()).approve(NPM, MAX_UINT_256);
    ERC20(IUniswapV3Pool(POOL).token1()).approve(NPM, MAX_UINT_256);
    ERC20(IUniswapV3Pool(POOL).token0()).approve(FEE_SPLITTER, MAX_UINT_256);
    ERC20(IUniswapV3Pool(POOL).token1()).approve(FEE_SPLITTER, MAX_UINT_256);
  }

  function bootstrapLock(
    AddLiquidity memory params
  ) external returns (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    require(_isBootstrapOngoing(), 'EXIT10: Bootstrap ended');

    _depositTokens(params.amount0Desired, params.amount1Desired);

    (tokenId, liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(params);

    bootstrapAmount += liquidityAdded;
    BOOT.mint(params.depositor, liquidityAdded * TOKEN_MULTIPLIER);

    _safeTransferTokens(params.depositor, params.amount0Desired - amountAdded0, params.amount1Desired - amountAdded1);
  }

  function createBond(
    AddLiquidity memory params
  ) external returns (uint256 bondID, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    _requireNoExitMode();
    require(!_isBootstrapOngoing(), 'EXIT10: Bootstrap ongoing');
    claimAndDistributeFees();

    _depositTokens(params.amount0Desired, params.amount1Desired);

    (, liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(params);

    bondID = NFT.mint(params.depositor);

    BondData memory bondData;
    bondData.bondAmount = liquidityAdded;
    bondData.startTime = uint64(block.timestamp);
    bondData.status = BondStatus.active;
    idToBondData[bondID] = bondData;

    pendingAmount += liquidityAdded;

    _safeTransferTokens(params.depositor, params.amount0Desired - amountAdded0, params.amount1Desired - amountAdded1);
    emit CreateBond(params.depositor, bondID, liquidityAdded);
  }

  function cancelBond(
    uint256 bondID,
    RemoveLiquidity memory params
  ) external returns (uint256 amountRemoved0, uint256 amountRemoved1) {
    BondData memory bond = idToBondData[bondID];
    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);
    claimAndDistributeFees();

    idToBondData[bondID].status = BondStatus.cancelled;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    _collect(msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    pendingAmount -= params.liquidity;

    emit CancelBond(msg.sender, bondID, amountRemoved0, amountRemoved1);
  }

  function convertBond(
    uint256 bondID,
    RemoveLiquidity memory params
  ) external returns (uint256 boostTokenAmount, uint256 exitTokenAmount) {
    _requireNoExitMode();

    BondData memory bond = idToBondData[bondID];
    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);
    claimAndDistributeFees();

    idToBondData[bondID].status = BondStatus.converted;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    pendingAmount -= params.liquidity;

    uint256 accruedBoostLiquidity = _getAccruedAmount(bond);

    idToBondData[bondID].claimedBoostAmount = accruedBoostLiquidity;
    reserveAmount += accruedBoostLiquidity; // Increase the amount of the reserve

    boostTokenAmount = accruedBoostLiquidity * TOKEN_MULTIPLIER;
    BLP.mint(msg.sender, boostTokenAmount);

    uint256 remainingLiquidity = bond.bondAmount - accruedBoostLiquidity;
    exitTokenAmount = (remainingLiquidity * TOKEN_MULTIPLIER) / LP_PER_USD;
    _mintExitCapped(msg.sender, exitTokenAmount);

    emit ConvertBond(msg.sender, bondID, bond.bondAmount, boostTokenAmount, exitTokenAmount);
  }

  function redeem(RemoveLiquidity memory params) external returns (uint256 amountRemoved0, uint256 amountRemoved1) {
    uint256 amount = params.liquidity;
    _requireValidAmount(amount);
    claimAndDistributeFees();

    reserveAmount -= amount;
    BLP.burn(msg.sender, amount * TOKEN_MULTIPLIER);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    _collect(msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    emit Redeem(msg.sender, amountRemoved0, amountRemoved1);
  }

  function exit10() external {
    _requireOutOfTickRange();
    claimAndDistributeFees();

    inExitMode = true;

    _stopExitRewards();
    exitTotalSupply = EXIT.totalSupply();
    finalExitAmount = uint128(_liquidityAmount() - (pendingAmount + reserveAmount));
    uint256 exitBucket;

    if (POOL.token1() == TOKEN_IN) {
      (exitBucket, ) = _decreaseLiquidity(
        RemoveLiquidity({ liquidity: uint128(finalExitAmount), amount0Min: 0, amount1Min: 0, deadline: DEADLINE })
      );
      _collect(address(this), uint128(exitBucket), 0);
    } else {
      (, exitBucket) = _decreaseLiquidity(
        RemoveLiquidity({ liquidity: uint128(finalExitAmount), amount0Min: 0, amount1Min: 0, deadline: DEADLINE })
      );
      _collect(address(this), 0, uint128(exitBucket));
    }

    // Total initial deposits that needs to be returned to bootsrappers
    exitBootstrap = (bootstrapAmount * exitBucket) / finalExitAmount;
    exitLiquidity = exitBucket - exitBootstrap;
    // 30% of the exitLiquidity goes to Bootstrappers+Team+EarlyBackers.
    uint256 share = exitLiquidity / 10;
    // Initial deposit plus 10% of the Exit Bucket
    exitBootstrap += share;
    // 20% of the ExitLiquidity
    exitTeamPlusBackers = share * 2;
    // 70% Exit Token holders
    exitLiquidity -= share * 3;

    _safeTransferToken(TOKEN_OUT, STO, exitTeamPlusBackers);
  }

  function bootstrapClaim() external {
    uint256 claim = _safeTokenClaim(
      BOOT,
      ERC20(BOOT).balanceOf(msg.sender) / TOKEN_MULTIPLIER,
      exitBootstrap,
      bootstrapAmount,
      exitBootstrapClaimed
    );

    exitBootstrapClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);
  }

  function exitClaim() external {
    uint256 claim = _safeTokenClaim(
      EXIT,
      ERC20(EXIT).balanceOf(msg.sender),
      exitLiquidity,
      exitTotalSupply,
      exitLiquidityClaimed
    );

    exitLiquidityClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);
  }

  function getBondData(
    uint256 bondID
  )
    external
    view
    returns (uint256 bondAmount, uint256 claimedBoostAmount, uint64 startTime, uint64 endTime, uint8 status)
  {
    BondData memory bond = idToBondData[bondID];
    return (bond.bondAmount, bond.claimedBoostAmount, bond.startTime, bond.endTime, uint8(bond.status));
  }

  function getTreasury() external view returns (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) {
    pending = pendingAmount;
    reserve = reserveAmount;
    bootstrap = bootstrapAmount;
    exit = _exitAmount();
  }

  function getAccruedAmount(uint256 bondID) external view returns (uint256) {
    BondData memory bond = idToBondData[bondID];

    if (bond.status != BondStatus.active) {
      return 0;
    }

    return _getAccruedAmount(bond);
  }

  function claimAndDistributeFees() public {
    (uint256 amountCollected0, uint256 amountCollected1) = _collect(address(this), MAX_UINT_128, MAX_UINT_128);

    if (_liquidityAmount() != 0) {
      uint256 bootstrapFees0 = (bootstrapAmount * amountCollected0) / _liquidityAmount();
      uint256 bootstrapFees1 = (bootstrapAmount * amountCollected1) / _liquidityAmount();

      if (bootstrapFees0 != 0 && bootstrapFees1 != 0) {
        (, uint256 amountAdded0, uint256 amountAdded1) = INPM(NPM).increaseLiquidity(
          INPM.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: bootstrapFees0,
            amount1Desired: bootstrapFees1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: DEADLINE
          })
        );

        amountCollected0 -= amountAdded0;
        amountCollected1 -= amountAdded1;
      }
    }

    if (amountCollected0 + amountCollected1 != 0)
      FeeSplitter(FEE_SPLITTER).collectFees(
        pendingAmount,
        bootstrapAmount + reserveAmount + _exitAmount(),
        amountCollected0,
        amountCollected1
      );
  }

  function _stopExitRewards() internal {
    MasterchefExit mc = MasterchefExit(MASTERCHEF);
    uint256 distributedRewards = (mc.rewardRate() * (block.timestamp - (mc.periodFinish() - mc.REWARDS_DURATION()))) /
      mc.PRECISION();
    EXIT.burn(MASTERCHEF, LP_EXIT_REWARD - distributedRewards);
  }

  function _safeTokenClaim(
    BaseToken _token,
    uint256 _amount,
    uint256 _externalSum,
    uint256 _supply,
    uint256 _claimed
  ) internal returns (uint256 _claim) {
    _requireExitMode();
    _requireValidAmount(_amount);

    _token.burn(msg.sender, ERC20(_token).balanceOf(msg.sender));
    _claim = (_amount * _externalSum) / _supply;
    _claim = (_claimed + _claim <= _supply) ? _claim : _supply - _claimed;
  }

  function _depositTokens(uint256 _amount0, uint256 _amount1) internal {
    ERC20(POOL.token0()).safeTransferFrom(msg.sender, address(this), _amount0);
    ERC20(POOL.token1()).safeTransferFrom(msg.sender, address(this), _amount1);
  }

  function _safeTransferTokens(address _recipient, uint256 _amount0, uint256 _amount1) internal {
    _safeTransferToken(POOL.token0(), _recipient, _amount0);
    _safeTransferToken(POOL.token1(), _recipient, _amount1);
  }

  function _safeTransferToken(address _token, address _recipient, uint256 _amount) internal {
    if (_amount != 0) ERC20(_token).safeTransfer(_recipient, _amount);
  }

  function _mintExitCapped(address recipient, uint256 amount) internal {
    uint256 newSupply = EXIT.totalSupply() + amount;
    uint256 mintAmount = newSupply > MAX_EXIT_SUPPLY ? MAX_EXIT_SUPPLY - amount : amount;
    if (mintAmount != 0) EXIT.mint(recipient, mintAmount);

    emit MintExit(recipient, mintAmount);
  }

  function _exitAmount() internal view returns (uint256 _exitBucket) {
    if (positionId == 0) return 0;
    _exitBucket = inExitMode ? finalExitAmount : _liquidityAmount() - (pendingAmount + reserveAmount + bootstrapAmount);
  }

  function _liquidityAmount() internal view returns (uint128 _liquidity) {
    if (positionId != 0) (, , , , , , , _liquidity, , , , ) = INPM(NPM).positions(positionId);
  }

  function _currentTick() internal view returns (int24 _tick) {
    (, _tick, , , , , ) = POOL.slot0();
  }

  function _getAccruedAmount(BondData memory _params) internal view returns (uint256 accruedAmount) {
    if (_params.startTime != 0) {
      uint256 bondDuration = 1e18 * (block.timestamp - _params.startTime);
      accruedAmount = (_params.bondAmount * bondDuration) / (bondDuration + ACCRUAL_PARAMETER);
      //assert(accruedAmount < _params.bondAmount); // we leave it as a comment so we can uncomment it for automated testing tools
    }
  }

  function _isBootstrapOngoing() internal view returns (bool) {
    return (block.timestamp < DEPLOYMENT_TIMESTAMP + BOOTSTRAP_PERIOD);
  }

  function _requireExitMode() internal view {
    require(inExitMode, 'EXIT10: Not in Exit mode');
  }

  function _requireNoExitMode() internal view {
    require(!inExitMode, 'EXIT10: In Exit mode');
  }

  function _requireOutOfTickRange() internal view {
    // Uniswap's price is recorded as token1/token0
    // https://github.com/timeless-fi/uniswap-poor-oracle.git
    if (TOKEN_IN > TOKEN_OUT) {
      require(_currentTick() <= TICK_LOWER, 'EXIT10: Current Tick not below TICK_LOWER');
    } else {
      require(_currentTick() >= TICK_UPPER, 'EXIT10: Current Tick not above TICK_UPPER');
    }
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == NFT.ownerOf(_bondID), 'EXIT10: Caller must own the bond');
  }

  function _requireValidAmount(uint256 _amount) internal pure {
    require(_amount != 0, 'EXIT10: Amount must be != 0');
  }

  function _requireActiveStatus(BondStatus _status) internal pure {
    require(_status == BondStatus.active, 'EXIT10: Bond must be active');
  }

  function _requireEqualLiquidity(uint256 _liquidityA, uint256 _liquidityB) internal pure {
    require(_liquidityA == _liquidityB, 'EXIT10: Incorrect liquidity amount');
  }
}
