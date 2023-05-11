// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { OracleLibrary } from '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
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
  using Math for uint256;

  struct DeployParams {
    address NFT;
    address STO;
    address BOOT;
    address BLP;
    address EXIT;
    address masterchef; // EXIT/USDC Stakers
    address feeSplitter; // Distribution to STO + BOOT and BLP stakers
    address beneficiary; // Address to receive fees if pool goes back into range after Exit10
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
  uint256 public bootstrapBucketFinal;
  uint256 public exitBucketFinal;

  // EXIT TOKEN
  uint256 public exitTokenSupplyFinal;
  uint256 public exitTokenRewardsFinal;

  // BOOT TOKEN
  uint256 public bootstrapRewardsPlusRefund;

  // STO TOKEN
  uint256 public teamPlusBackersRewards;

  uint256 public bootstrapFees0;
  uint256 public bootstrapFees1;

  bool public isBootstrapCapReached;
  bool public inExitMode;
  bool private hasUpdatedRewards;

  mapping(uint256 => BondData) private idToBondData;

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
  address public immutable BENEFICIARY;

  uint256 public immutable BOOTSTRAP_FINISH;
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
    BENEFICIARY = params_.beneficiary;

    BOOTSTRAP_FINISH = params_.bootstrapPeriod + block.timestamp;
    BOOTSTRAP_TARGET = params_.bootstrapTarget;
    BOOTSTRAP_CAP = params_.bootstrapCap;
    ACCRUAL_PARAMETER = params_.accrualParameter;
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
    _requireNoExitMode();
    require(_isBootstrapOngoing(), 'EXIT10: Bootstrap ended');
    require(!isBootstrapCapReached, 'EXIT10: Bootstrap cap reached');

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
        (uint256 amountCollected0, uint256 amountCollected1) = _collect(
          address(this),
          uint128(amountRemoved0),
          uint128(amountRemoved1)
        );

        liquidityAdded -= uint128(diff);
        amountAdded0 -= amountCollected0;
        amountAdded1 -= amountCollected1;
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

    if (!hasUpdatedRewards) {
      EXIT.mint(MASTERCHEF, LP_EXIT_REWARD);
      MasterchefExit(MASTERCHEF).updateRewards(LP_EXIT_REWARD);
      hasUpdatedRewards = true;
    }

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
    _requireEqualValues(bond.bondAmount, params.liquidity);

    claimAndDistributeFees();

    idToBondData[bondID].status = BondStatus.cancelled;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    (uint256 amountCollected0, uint256 amountCollected1) = _collect(
      msg.sender,
      uint128(amountRemoved0),
      uint128(amountRemoved1)
    );

    pendingBucket -= params.liquidity;

    emit CancelBond(msg.sender, bondID, amountCollected0, amountCollected1);
  }

  function convertBond(
    uint256 bondID,
    RemoveLiquidity memory params
  ) external returns (uint256 boostTokenAmount, uint256 exitTokenAmount) {
    _requireNoExitMode();
    _requireCallerOwnsBond(bondID);
    BondData memory bond = idToBondData[bondID];
    _requireActiveStatus(bond.status);
    _requireEqualValues(bond.bondAmount, params.liquidity);

    claimAndDistributeFees();

    uint256 accruedLiquidity = _getAccruedLiquidity(bond);
    boostTokenAmount = accruedLiquidity * TOKEN_MULTIPLIER;

    idToBondData[bondID].status = BondStatus.converted;
    idToBondData[bondID].endTime = uint64(block.timestamp);
    idToBondData[bondID].claimedBoostAmount = boostTokenAmount;

    pendingBucket -= params.liquidity;
    reserveBucket += accruedLiquidity;

    uint256 exitAccrued = _getExitAmount(bond.bondAmount - accruedLiquidity);
    exitTokenAmount = exitAccrued + ((exitAccrued * EXIT_DISCOUNT) / PERCENT_BASE);

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
    (uint256 amountCollected0, uint256 amountCollected1) = _collect(
      msg.sender,
      uint128(amountRemoved0),
      uint128(amountRemoved1)
    );

    emit Redeem(msg.sender, amountToBurn, amountCollected0, amountCollected1);
  }

  function exit10() external {
    _requireNoExitMode();
    _requireOutOfTickRange();

    claimAndDistributeFees();

    inExitMode = true;

    // Stop and burn Exit rewards.
    EXIT.burn(MASTERCHEF, MasterchefExit(MASTERCHEF).stopRewards(LP_EXIT_REWARD));
    exitTokenSupplyFinal = EXIT.totalSupply();
    exitBucketFinal = _liquidityAmount() - (pendingBucket + reserveBucket);
    bootstrapBucketFinal = bootstrapBucket;
    bootstrapBucket = 0;

    RemoveLiquidity memory rmParams = RemoveLiquidity({
      liquidity: uint128(exitBucketFinal),
      amount0Min: 0,
      amount1Min: 0,
      deadline: DEADLINE
    });

    uint256 exitBucketRewards;

    if (TOKEN_OUT < TOKEN_IN) {
      (exitBucketRewards, ) = _decreaseLiquidity(rmParams);
      (exitBucketRewards, ) = _collect(address(this), uint128(exitBucketRewards), 0);
    } else {
      (, exitBucketRewards) = _decreaseLiquidity(rmParams);
      (, exitBucketRewards) = _collect(address(this), 0, uint128(exitBucketRewards));
    }

    // Total initial deposits that needs to be returned to bootsrappers
    uint256 bootstrapRefund = exitBucketFinal != 0 ? (bootstrapBucketFinal * exitBucketRewards) / exitBucketFinal : 0;

    (bootstrapRewardsPlusRefund, teamPlusBackersRewards, exitTokenRewardsFinal) = _calculateFinalShares(
      bootstrapRefund,
      exitBucketRewards,
      bootstrapBucketFinal,
      exitTokenSupplyFinal
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
    uint256 bootBalance = IERC20(BOOT).balanceOf(msg.sender);

    claim = _safeTokenClaim(BOOT, bootBalance / TOKEN_MULTIPLIER, bootstrapBucketFinal, bootstrapRewardsPlusRefund);

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(BOOT), bootBalance, claim);
  }

  function stoClaim() external returns (uint256 claim) {
    BaseToken sto = STO;
    uint256 stoBalance = IERC20(sto).balanceOf(msg.sender);
    claim = _safeTokenClaim(sto, stoBalance, STOToken(address(sto)).MAX_SUPPLY(), teamPlusBackersRewards);

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(STO), stoBalance, claim);
  }

  function exitClaim() external returns (uint256 claim) {
    BaseToken exit = EXIT;
    uint256 exitBalance = IERC20(exit).balanceOf(msg.sender);
    claim = _safeTokenClaim(exit, exitBalance, exitTokenSupplyFinal, exitTokenRewardsFinal);

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);

    emit ClaimRewards(msg.sender, address(exit), exitBalance, claim);
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

    if (amountCollected0 + amountCollected1 + bootstrapFees0 + bootstrapFees1 == 0) return;

    if (!inExitMode) {
      uint128 _totalLiquidityBefore = _liquidityAmount();
      if (_totalLiquidityBefore != 0) {
        uint256 cacheBootstrapFees0 = bootstrapBucket.mulDiv(
          amountCollected0,
          _totalLiquidityBefore,
          Math.Rounding.Down
        );
        uint256 cacheBootstrapFees1 = bootstrapBucket.mulDiv(
          amountCollected1,
          _totalLiquidityBefore,
          Math.Rounding.Down
        );

        bootstrapFees0 += cacheBootstrapFees0;
        bootstrapFees1 += cacheBootstrapFees1;
        amountCollected0 -= cacheBootstrapFees0;
        amountCollected1 -= cacheBootstrapFees1;

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
            // Liquidity Added Success
            unchecked {
              bootstrapFees0 -= amountAdded0;
              bootstrapFees1 -= amountAdded1;
            }
          } catch {
            // Liquidity Added Fail
            // Continue and distribute amountCollected
          }
        }
      }

      if (TOKEN_IN < TOKEN_OUT) {
        (amountCollected0, amountCollected1) = (amountCollected1, amountCollected0);
      }

      // In case Exit10 is called and we need to distribute pending bootstrap fees
      if (_isOutOfTickRange()) {
        if (TOKEN_IN < TOKEN_OUT) {
          (bootstrapFees0, bootstrapFees1) = (bootstrapFees1, bootstrapFees0);
        }

        amountCollected0 += bootstrapFees0;
        amountCollected1 += bootstrapFees1;
        bootstrapFees0 = 0;
        bootstrapFees1 = 0;
      }

      FeeSplitter(FEE_SPLITTER).collectFees(
        pendingBucket,
        _totalLiquidityBefore - bootstrapBucket,
        amountCollected0,
        amountCollected1
      );
    } else {
      // In case liquidity from Pending + Reserve buckets goes back in range after Exit10
      _safeTransferTokens(BENEFICIARY, amountCollected0, amountCollected1);
    }

    emit ClaimAndDistributeFees(msg.sender, amountCollected0, amountCollected1);
  }

  function _getExitAmount(uint256 _liquidity) internal view returns (uint256) {
    uint256 bootstrapTargetLiquidity = (BOOTSTRAP_TARGET * LIQUIDITY_PER_USD) / TOKEN_OUT_DECIMALS;

    uint256 percentFromTaget = (bootstrapTargetLiquidity == 0)
      ? 0
      : (bootstrapBucket * PERCENT_BASE) / bootstrapTargetLiquidity;

    uint256 projectedLiquidityPerExit = (LIQUIDITY_PER_USD * Math.max(percentFromTaget, 5000)) / PERCENT_BASE;

    uint256 actualLiquidityPerExit = _getActualLiquidityPerExit(_exitBucket());

    uint256 liquidityPerExit = Math.max(actualLiquidityPerExit, projectedLiquidityPerExit);

    return ((_liquidity * DECIMAL_PRECISION) / liquidityPerExit);
  }

  function _safeTokenClaim(
    BaseToken _token,
    uint256 _amount,
    uint256 _finalTotalSupply,
    uint256 _rewardsFinalTotalSupply
  ) internal returns (uint256 _claimableRewards) {
    _requireExitMode();
    require(_amount != 0, 'EXIT10: Amount must be != 0');

    _token.burn(msg.sender, IERC20(_token).balanceOf(msg.sender));
    _claimableRewards = _amount.mulDiv(_rewardsFinalTotalSupply, _finalTotalSupply, Math.Rounding.Down);
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
    _exitAmount = inExitMode ? 0 : _liquidityAmount() - (pendingBucket + reserveBucket + bootstrapBucket);
  }

  function _liquidityAmount() internal view returns (uint128 _liquidity) {
    if (positionId != 0) (, , , , , , , _liquidity, , , , ) = INPM(NPM).positions(positionId);
  }

  function _currentTick() internal view returns (int24 _tick) {
    (, _tick, , , , , ) = POOL.slot0();
  }

  function _getAccruedLiquidity(BondData memory _params) internal view returns (uint256 accruedAmount) {
    uint256 bondDuration = block.timestamp - _params.startTime;
    accruedAmount = (_params.bondAmount * bondDuration) / (bondDuration + ACCRUAL_PARAMETER);
  }

  function _isBootstrapOngoing() internal view returns (bool) {
    return (block.timestamp < BOOTSTRAP_FINISH);
  }

  function _isOutOfTickRange() internal view returns (bool) {
    (int24 blockStartTick, ) = OracleLibrary.getBlockStartingTickAndLiquidity(address(POOL));
    int24 currentTick = _currentTick();
    int24 tickDiff = blockStartTick > currentTick ? blockStartTick - currentTick : currentTick - blockStartTick;
    bool limit = (tickDiff < 100); // 100 ticks is about 1% in price difference
    if (TOKEN_IN > TOKEN_OUT) {
      return (currentTick <= TICK_LOWER && limit);
    } else {
      return (currentTick >= TICK_UPPER && limit);
    }
  }

  function _requireExitMode() internal view {
    require(inExitMode, 'EXIT10: Not in Exit mode');
  }

  function _requireNoExitMode() internal view {
    require(!inExitMode, 'EXIT10: In Exit mode');
  }

  function _requireOutOfTickRange() internal view {
    require(_isOutOfTickRange(), 'EXIT10: Not out of tick range');
  }

  function _requireCallerOwnsBond(uint256 _bondID) internal view {
    require(msg.sender == NFT.ownerOf(_bondID), 'EXIT10: Caller must own the bond');
  }

  function _requireActiveStatus(BondStatus _status) internal pure {
    require(_status == BondStatus.active, 'EXIT10: Bond must be active');
  }

  function _requireEqualValues(uint256 _valueA, uint256 _valueB) internal pure {
    require(_valueA == _valueB, 'EXIT10: Amounts do not match');
  }

  function _getActualLiquidityPerExit(uint256 _exitBucketAmount) internal pure returns (uint256) {
    uint256 exitTokenShareOfBucket = (_exitBucketAmount * 7000) / PERCENT_BASE;
    return (exitTokenShareOfBucket * DECIMAL_PRECISION) / MAX_EXIT_SUPPLY;
  }

  function _calculateFinalShares(
    uint256 _refund,
    uint256 _totalRewards,
    uint256 _bootstrapBucket,
    uint256 _exitSupply
  ) internal pure returns (uint256 _bootRewards, uint256 _stoRewards, uint256 _exitRewards) {
    uint256 exitBucketMinusRefund = _totalRewards - _refund;
    uint256 tenPercent = exitBucketMinusRefund / 10;

    if (_bootstrapBucket != 0) {
      // Initial deposit plus 10% of the Exit Bucket
      _bootRewards = _refund + tenPercent;
    }
    // 20% of the ExitLiquidity
    _stoRewards = tenPercent << 1;

    if (_exitSupply != 0) {
      // 70% Exit Token holders
      _exitRewards = _totalRewards - (_bootRewards + _stoRewards);
    } else {
      _stoRewards = _totalRewards - _bootRewards;
    }
  }
}
