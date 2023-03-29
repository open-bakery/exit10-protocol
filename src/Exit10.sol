// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { INPM } from './interfaces/INonfungiblePositionManager.sol';
import { IUniswapV3Pool } from './interfaces/IUniswapV3Pool.sol';
import { INFT } from './interfaces/INFT.sol';
import { BaseToken } from './BaseToken.sol';
import { FeeSplitter } from './FeeSplitter.sol';
import { UniswapBase } from './UniswapBase.sol';
import { MasterchefExit } from './MasterchefExit.sol';
import { STOToken } from './STOToken.sol';

contract Exit10 is UniswapBase {
  using SafeERC20 for IERC20;

  struct DeployParams {
    address NFT;
    address STO;
    address BOOT;
    address BLP;
    address EXIT;
    address masterchef; // EXIT/USDC Stakers
    address feeSplitter; // Distribution to STO + BOOT and BLP stakers
    uint256 bootstrapPeriod;
    uint256 bootstrapTarget;
    uint256 bootstrapCap;
    uint256 liquidityPerUsd; // Amount of liquidity per USD that is minted passed the upper range of the 500-10000 pool
    uint256 exitDiscount;
    uint256 accrualParameter; // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.
  }

  struct BondData {
    uint256 bondAmount;
    uint256 claimedBoostAmount;
    uint64 startTime;
    uint64 endTime;
    BondStatus status;
  }

  enum BondStatus {
    nonExistent,
    active,
    cancelled,
    converted
  }

  uint256 private pendingBucket;
  uint256 private reserveBucket;
  uint256 private bootstrapBucket;
  uint256 private bootstrapBucketFinal;
  uint256 private exitBucketFinal;

  // EXIT TOKEN
  uint256 public exitTokenSupplyFinal;
  uint256 public exitTokenRewardsFinal;
  uint256 public exitTokenRewardsClaimed;

  // BOOT TOKEN
  uint256 public bootstrapRewardsPlusRefund;
  uint256 public bootstrapRewardsPlusRefundClaimed;

  // STO TOKEN
  uint256 public teamPlusBackersRewards;
  uint256 public teamPlusBackersRewardsClaimed;

  bool public isBootstrapCapReached;
  bool public inExitMode;

  mapping(uint256 => BondData) private idToBondData;
  mapping(address => uint256) public bootstrapDeposit;

  uint256 public constant TOKEN_MULTIPLIER = 1e8;
  uint256 public constant LP_EXIT_REWARD = 3_000_000 ether;
  uint256 public constant BONDERS_EXIT_REWARD = 7_000_000 ether;
  uint256 public constant MAX_EXIT_SUPPLY = LP_EXIT_REWARD + BONDERS_EXIT_REWARD;
  uint128 private constant MAX_UINT_128 = type(uint128).max;
  uint256 private constant MAX_UINT_256 = type(uint256).max;
  uint256 private constant DEADLINE = 1e10;
  uint256 private constant DECIMAL_PRECISION = 1e18;
  uint256 private constant PERCENT_BASE = 10000;

  BaseToken public immutable STO;
  BaseToken public immutable BOOT;
  BaseToken public immutable BLP;
  BaseToken public immutable EXIT;
  INFT public immutable NFT;

  address public immutable MASTERCHEF;
  address public immutable FEE_SPLITTER;

  uint256 public immutable DEPLOYMENT_TIMESTAMP;
  uint256 public immutable BOOTSTRAP_PERIOD;
  uint256 public immutable BOOTSTRAP_TARGET;
  uint256 public immutable BOOTSTRAP_CAP;
  uint256 public immutable ACCRUAL_PARAMETER;
  uint256 public immutable LIQUIDITY_PER_USD;
  uint256 public immutable EXIT_DISCOUNT;
  uint256 public immutable TOKEN_OUT_DECIMALS;

  event BootstrapLock(
    address indexed recipient,
    uint256 lockAmount,
    uint256 amountAdded0,
    uint256 amountAdded1,
    uint256 bootTokensMinted
  );
  event CreateBond(
    address indexed recipient,
    uint256 bondID,
    uint256 bondAmount,
    uint256 amountAdded0,
    uint256 amountAdded1
  );
  event CancelBond(address indexed caller, uint256 bondID, uint256 amountReturned0, uint256 amountReturned1);
  event ConvertBond(
    address indexed caller,
    uint256 bondID,
    uint256 bondAmount,
    uint256 blpClaimed,
    uint256 exitClaimed
  );
  event Redeem(address indexed caller, uint256 burnedBLP, uint256 amountReturned0, uint256 amountReturned1);
  event Exit(
    address indexed caller,
    uint256 time,
    uint256 bootstrapRefund,
    uint256 bootstrapRewards,
    uint256 teamPlusBackersRewards,
    uint256 exitTokenRewards
  );
  event ClaimRewards(address indexed caller, address indexed token, uint256 amountBurned, uint256 amountClaimed);
  event ClaimAndDistributeFees(address indexed caller, uint256 amountClaimed0, uint256 amountClaimed1);
  event MintExit(address indexed recipient, uint256 amount);

  constructor(BaseDeployParams memory baseParams_, DeployParams memory params_) UniswapBase(baseParams_) {
    STO = STOToken(params_.STO);
    BOOT = BaseToken(params_.BOOT);
    BLP = BaseToken(params_.BLP);
    EXIT = BaseToken(params_.EXIT);
    NFT = INFT(params_.NFT);

    MASTERCHEF = params_.masterchef;
    FEE_SPLITTER = params_.feeSplitter;

    DEPLOYMENT_TIMESTAMP = block.timestamp;
    BOOTSTRAP_PERIOD = params_.bootstrapPeriod;
    BOOTSTRAP_TARGET = params_.bootstrapTarget;
    BOOTSTRAP_CAP = params_.bootstrapCap;
    ACCRUAL_PARAMETER = params_.accrualParameter * DECIMAL_PRECISION;
    LIQUIDITY_PER_USD = params_.liquidityPerUsd;
    EXIT_DISCOUNT = params_.exitDiscount;
    TOKEN_OUT_DECIMALS = 10 ** ERC20(TOKEN_OUT).decimals();

    IERC20(IUniswapV3Pool(POOL).token0()).approve(NPM, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token1()).approve(NPM, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token0()).approve(FEE_SPLITTER, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token1()).approve(FEE_SPLITTER, MAX_UINT_256);
  }

  function bootstrapLock(
    AddLiquidity memory params
  ) external payable returns (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    require(_isBootstrapOngoing(), 'EXIT10: Bootstrap ended');

    _depositTokens(params.amount0Desired, params.amount1Desired);

    (tokenId, liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(params);

    bootstrapBucket += liquidityAdded;

    if (BOOTSTRAP_CAP != 0) {
      if (bootstrapBucket > BOOTSTRAP_CAP) {
        uint256 diff;
        unchecked {
          diff = bootstrapBucket - BOOTSTRAP_CAP;
        }
        (uint256 amountRemoved0, uint256 amountRemoved1) = _decreaseLiquidity(
          UniswapBase.RemoveLiquidity({ liquidity: uint128(diff), amount0Min: 0, amount1Min: 0, deadline: DEADLINE })
        );
        _collect(address(this), uint128(amountRemoved0), uint128(amountRemoved1));

        liquidityAdded -= uint128(diff);
        amountAdded0 -= amountRemoved0;
        amountAdded1 -= amountRemoved1;
        bootstrapBucket = BOOTSTRAP_CAP;
        isBootstrapCapReached = true;
      }
    }

    uint256 mintAmount = liquidityAdded * TOKEN_MULTIPLIER;
    BOOT.mint(params.depositor, mintAmount);

    _safeTransferTokens(params.depositor, params.amount0Desired - amountAdded0, params.amount1Desired - amountAdded1);

    emit BootstrapLock(params.depositor, liquidityAdded, amountAdded0, amountAdded1, mintAmount);
  }

  function createBond(
    AddLiquidity memory params
  ) external payable returns (uint256 bondID, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
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

    pendingBucket += liquidityAdded;

    _safeTransferTokens(params.depositor, params.amount0Desired - amountAdded0, params.amount1Desired - amountAdded1);

    emit CreateBond(params.depositor, bondID, liquidityAdded, amountAdded0, amountAdded1);
  }

  function cancelBond(
    uint256 bondID,
    RemoveLiquidity memory params
  ) external returns (uint256 amountRemoved0, uint256 amountRemoved1) {
    _requireCallerOwnsBond(bondID);
    BondData memory bond = idToBondData[bondID];
    _requireActiveStatus(bond.status);
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);

    claimAndDistributeFees();

    idToBondData[bondID].status = BondStatus.cancelled;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    _collect(msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    pendingBucket -= params.liquidity;

    emit CancelBond(msg.sender, bondID, amountRemoved0, amountRemoved1);
  }

  function convertBond(
    uint256 bondID,
    RemoveLiquidity memory params
  ) external returns (uint256 boostTokenAmount, uint256 exitTokenAmount) {
    _requireNoExitMode();
    _requireCallerOwnsBond(bondID);
    BondData memory bond = idToBondData[bondID];
    _requireActiveStatus(bond.status);
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);

    claimAndDistributeFees();

    uint256 accruedLiquidity = _getAccruedLiquidity(bond);
    boostTokenAmount = accruedLiquidity * TOKEN_MULTIPLIER;

    idToBondData[bondID].status = BondStatus.converted;
    idToBondData[bondID].endTime = uint64(block.timestamp);
    idToBondData[bondID].claimedBoostAmount = boostTokenAmount;

    pendingBucket -= params.liquidity;
    reserveBucket += accruedLiquidity;

    exitTokenAmount = _getDiscountedExitAmount((bond.bondAmount - accruedLiquidity), EXIT_DISCOUNT);

    BLP.mint(msg.sender, boostTokenAmount);
    _mintExitCapped(msg.sender, exitTokenAmount);

    emit ConvertBond(msg.sender, bondID, bond.bondAmount, boostTokenAmount, exitTokenAmount);
  }

  function redeem(RemoveLiquidity memory params) external returns (uint256 amountRemoved0, uint256 amountRemoved1) {
    claimAndDistributeFees();

    reserveBucket -= params.liquidity;

    uint256 amountToBurn = params.liquidity * TOKEN_MULTIPLIER;
    BLP.burn(msg.sender, amountToBurn);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    _collect(msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    emit Redeem(msg.sender, amountToBurn, amountRemoved0, amountRemoved1);
  }

  function exit10() external {
    _requireOutOfTickRange();
    claimAndDistributeFees();

    inExitMode = true;

    // Stop and burn Exit rewards.
    EXIT.burn(MASTERCHEF, MasterchefExit(MASTERCHEF).stopRewards(LP_EXIT_REWARD));
    exitTokenSupplyFinal = EXIT.totalSupply();
    exitBucketFinal = _liquidityAmount() - (pendingBucket + reserveBucket);
    bootstrapBucketFinal = bootstrapBucket;
    bootstrapBucket = 0;

    uint256 exitBucketRewards;

    RemoveLiquidity memory rmParams = RemoveLiquidity({
      liquidity: uint128(exitBucketFinal),
      amount0Min: 0,
      amount1Min: 0,
      deadline: DEADLINE
    });

    if (POOL.token1() == TOKEN_IN) {
      (exitBucketRewards, ) = _decreaseLiquidity(rmParams);
      _collect(address(this), uint128(exitBucketRewards), 0);
    } else {
      (, exitBucketRewards) = _decreaseLiquidity(rmParams);
      _collect(address(this), 0, uint128(exitBucketRewards));
    }

    // Total initial deposits that needs to be returned to bootsrappers
    uint256 bootstrapRefund = exitBucketFinal != 0 ? (bootstrapBucketFinal * exitBucketRewards) / exitBucketFinal : 0;

    (bootstrapRewardsPlusRefund, teamPlusBackersRewards, exitTokenRewardsFinal) = _calculateFinalShares(
      bootstrapRefund,
      exitBucketRewards
    );

    emit Exit(
      msg.sender,
      block.timestamp,
      bootstrapRefund,
      bootstrapRewardsPlusRefund - bootstrapRefund,
      teamPlusBackersRewards,
      exitTokenRewardsFinal
    );
  }

  function bootstrapClaim() external returns (uint256 claim) {
    _requireExitMode();
    uint256 bootBalance = IERC20(BOOT).balanceOf(msg.sender);
    claim = _safeTokenClaim(
      BOOT,
      bootBalance / TOKEN_MULTIPLIER,
      bootstrapBucketFinal,
      bootstrapRewardsPlusRefund,
      bootstrapRewardsPlusRefundClaimed
    );

    bootstrapRewardsPlusRefundClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(BOOT), bootBalance, claim);
  }

  function stoClaim() external {
    _requireExitMode();
    uint256 stoBalance = IERC20(STO).balanceOf(msg.sender);
    uint256 claim = _safeTokenClaim(
      STO,
      stoBalance,
      STOToken(address(STO)).MAX_SUPPLY(),
      teamPlusBackersRewards,
      teamPlusBackersRewardsClaimed
    );

    teamPlusBackersRewardsClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(STO), stoBalance, claim);
  }

  function exitClaim() external {
    _requireExitMode();
    uint256 exitBalance = IERC20(EXIT).balanceOf(msg.sender);
    uint256 claim = _safeTokenClaim(
      EXIT,
      exitBalance,
      exitTokenSupplyFinal,
      exitTokenRewardsFinal,
      exitTokenRewardsClaimed
    );

    exitTokenRewardsClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(EXIT), exitBalance, claim);
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

  function getBuckets() external view returns (uint256 pending, uint256 reserve, uint256 exit, uint256 bootstrap) {
    pending = pendingBucket;
    reserve = reserveBucket;
    bootstrap = bootstrapBucket;
    exit = _exitBucket();
  }

  function getAccruedAmount(uint256 bondID) external view returns (uint256) {
    BondData memory bond = idToBondData[bondID];

    if (bond.status != BondStatus.active) {
      return 0;
    }

    return _getAccruedLiquidity(bond);
  }

  function claimAndDistributeFees() public {
    (uint256 amountCollected0, uint256 amountCollected1) = _collect(address(this), MAX_UINT_128, MAX_UINT_128);

    if (amountCollected0 + amountCollected1 == 0) return;

    if (_liquidityAmount() != 0) {
      uint256 bootstrapFees0 = (bootstrapBucket * amountCollected0) / _liquidityAmount();
      uint256 bootstrapFees1 = (bootstrapBucket * amountCollected1) / _liquidityAmount();

      if (bootstrapFees0 != 0 && bootstrapFees1 != 0) {
        try
          INPM(NPM).increaseLiquidity(
            INPM.IncreaseLiquidityParams({
              tokenId: positionId,
              amount0Desired: bootstrapFees0,
              amount1Desired: bootstrapFees1,
              amount0Min: 0,
              amount1Min: 0,
              deadline: DEADLINE
            })
          )
        returns (uint128, uint256 amountAdded0, uint256 amountAdded1) {
          unchecked {
            amountCollected0 -= amountAdded0;
            amountCollected1 -= amountAdded1;
          }
        } catch {
          return;
        }
      }
    }
    FeeSplitter(FEE_SPLITTER).collectFees(
      pendingBucket,
      bootstrapBucket + reserveBucket + _exitBucket(),
      amountCollected0,
      amountCollected1
    );

    emit ClaimAndDistributeFees(msg.sender, amountCollected0, amountCollected1);
  }

  function _getDiscountedExitAmount(uint256 _liquidity, uint256 _discountPercentage) internal view returns (uint256) {
    return _addPercentToAmount(_getExitAmount(_liquidity), _discountPercentage);
  }

  function _getExitAmount(uint256 _liquidity) internal view returns (uint256) {
    uint256 percentFromTaget = _getPercentFromTarget(_liquidity) <= 5000 ? 5000 : _getPercentFromTarget(_liquidity);
    uint256 projectedLiquidityPerExit = (LIQUIDITY_PER_USD * percentFromTaget) / PERCENT_BASE;
    uint256 actualLiquidityPerExit = _getActualLiquidityPerExit(_exitBucket());
    uint256 liquidityPerExit = actualLiquidityPerExit > projectedLiquidityPerExit
      ? actualLiquidityPerExit
      : projectedLiquidityPerExit;
    return ((_liquidity * DECIMAL_PRECISION) / liquidityPerExit);
  }

  function _getPercentFromTarget(uint256 _amountBootstrapped) internal view returns (uint256) {
    uint256 bootstrapTargetLiquidity = _getLiquidityForBootsrapTarget();
    if (bootstrapTargetLiquidity == 0) return 0;
    return (_amountBootstrapped * PERCENT_BASE) / bootstrapTargetLiquidity;
  }

  function _getLiquidityForBootsrapTarget() internal view returns (uint256) {
    return (BOOTSTRAP_TARGET * LIQUIDITY_PER_USD) / TOKEN_OUT_DECIMALS;
  }

  function _safeTokenClaim(
    BaseToken _token,
    uint256 _amount,
    uint256 _supply,
    uint256 _externalSum,
    uint256 _claimed
  ) internal returns (uint256 _claim) {
    _requireExitMode();
    require(_amount != 0, 'EXIT10: Amount must be != 0');

    _token.burn(msg.sender, IERC20(_token).balanceOf(msg.sender));
    _claim = (_amount * _externalSum) / _supply;
    _claim = (_claimed + _claim <= _supply) ? _claim : _supply - _claimed;
  }

  function _depositTokens(uint256 _amount0, uint256 _amount1) internal {
    IERC20(POOL.token0()).safeTransferFrom(msg.sender, address(this), _amount0);
    IERC20(POOL.token1()).safeTransferFrom(msg.sender, address(this), _amount1);
  }

  function _safeTransferTokens(address _recipient, uint256 _amount0, uint256 _amount1) internal {
    _safeTransferToken(POOL.token0(), _recipient, _amount0);
    _safeTransferToken(POOL.token1(), _recipient, _amount1);
  }

  function _safeTransferToken(address _token, address _recipient, uint256 _amount) internal {
    if (_amount != 0) IERC20(_token).safeTransfer(_recipient, _amount);
  }

  function _mintExitCapped(address recipient, uint256 amount) internal {
    uint256 newSupply = EXIT.totalSupply() + amount;
    uint256 mintAmount = newSupply > MAX_EXIT_SUPPLY ? MAX_EXIT_SUPPLY - EXIT.totalSupply() : amount;
    if (mintAmount != 0) EXIT.mint(recipient, mintAmount);

    emit MintExit(recipient, mintAmount);
  }

  function _exitBucket() internal view returns (uint256 _exitAmount) {
    if (positionId == 0) return 0;
    _exitAmount = inExitMode ? exitBucketFinal : _liquidityAmount() - (pendingBucket + reserveBucket + bootstrapBucket);
  }

  function _liquidityAmount() internal view returns (uint128 _liquidity) {
    if (positionId != 0) (, , , , , , , _liquidity, , , , ) = INPM(NPM).positions(positionId);
  }

  function _currentTick() internal view returns (int24 _tick) {
    (, _tick, , , , , ) = POOL.slot0();
  }

  function _getAccruedLiquidity(BondData memory _params) internal view returns (uint256 accruedAmount) {
    if (_params.startTime != 0) {
      uint256 bondDuration = 1e18 * (block.timestamp - _params.startTime);
      accruedAmount = (_params.bondAmount * bondDuration) / (bondDuration + ACCRUAL_PARAMETER);
    }
  }

  function _isBootstrapOngoing() internal view returns (bool) {
    return (block.timestamp < DEPLOYMENT_TIMESTAMP + BOOTSTRAP_PERIOD && !isBootstrapCapReached);
  }

  function _requireExitMode() internal view {
    require(inExitMode, 'EXIT10: Not in Exit mode');
  }

  function _requireNoExitMode() internal view {
    require(!inExitMode, 'EXIT10: In Exit mode');
  }

  function _requireOutOfTickRange() internal view {
    if (TOKEN_IN > TOKEN_OUT) {
      require(_currentTick() <= TICK_LOWER, 'EXIT10: Current Tick not below TICK_LOWER');
    } else {
      require(_currentTick() >= TICK_UPPER, 'EXIT10: Current Tick not above TICK_UPPER');
    }
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == NFT.ownerOf(_bondID), 'EXIT10: Caller must own the bond');
  }

  function _requireActiveStatus(BondStatus _status) internal pure {
    require(_status == BondStatus.active, 'EXIT10: Bond must be active');
  }

  function _requireEqualLiquidity(uint256 _liquidityA, uint256 _liquidityB) internal pure {
    require(_liquidityA == _liquidityB, 'EXIT10: Incorrect liquidity amount');
  }

  function _addPercentToAmount(uint256 _amount, uint256 _percent) internal pure returns (uint256) {
    return _amount + ((_amount * _percent) / PERCENT_BASE);
  }

  function _getActualLiquidityPerExit(uint256 _exitBucketAmount) internal pure returns (uint256) {
    uint256 exitTokenShareOfBucket = (_exitBucketAmount * 7000) / PERCENT_BASE;
    return (exitTokenShareOfBucket * DECIMAL_PRECISION) / MAX_EXIT_SUPPLY;
  }

  function _calculateFinalShares(
    uint256 _refund,
    uint256 _totalRewards
  ) internal pure returns (uint256 _bootRewards, uint256 _stoRewards, uint256 _exitRewards) {
    uint256 exitBucketMinusRefund = _totalRewards - _refund;
    uint256 tenPercent = exitBucketMinusRefund / 10;
    // Initial deposit plus 10% of the Exit Bucket
    _bootRewards = _refund + tenPercent;
    // 20% of the ExitLiquidity
    _stoRewards = tenPercent * 2;
    // 70% Exit Token holders
    _exitRewards = exitBucketMinusRefund - tenPercent * 3;
  }
}
