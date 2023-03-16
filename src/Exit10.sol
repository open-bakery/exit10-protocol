// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
import { INPM } from './interfaces/INonfungiblePositionManager.sol';
import { IUniswapV3Pool } from './interfaces/IUniswapV3Pool.sol';
import { INFT } from './interfaces/INFT.sol';
import { IExit10 } from './interfaces/IExit10.sol';
import { BaseToken } from './BaseToken.sol';
import { FeeSplitter } from './FeeSplitter.sol';
import { IUniswapBase, UniswapBase } from './UniswapBase.sol';
import { MasterchefExit } from './MasterchefExit.sol';

//import 'forge-std/Test.sol';

contract Exit10 is IExit10, IUniswapBase, UniswapBase {
  using SafeERC20 for IERC20;

  uint256 private pendingBucket;
  uint256 private reserveBucket;
  uint256 private bootstrapBucket;
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

  bool public inExitMode;

  mapping(uint256 => BondData) private idToBondData;
  mapping(address => uint256) public bootstrapDeposit;

  // --- Constants ---
  uint256 public constant TOKEN_MULTIPLIER = 1e8;
  uint256 public constant LP_EXIT_REWARD = 3_000_000 ether;
  uint256 public constant BONDERS_EXIT_REWARD = 7_000_000 ether;
  uint256 public constant MAX_EXIT_SUPPLY = LP_EXIT_REWARD + BONDERS_EXIT_REWARD;
  uint256 private constant MAX_UINT_256 = type(uint256).max;
  uint128 private constant MAX_UINT_128 = type(uint128).max;
  uint256 private constant DECIMAL_PRECISION = 1e18;
  uint256 private constant DEADLINE = 1e10;

  BaseToken public immutable EXIT;
  BaseToken public immutable BLP;
  BaseToken public immutable BOOT;
  INFT public immutable NFT;

  address public immutable STO;
  address public immutable MASTERCHEF;
  address public immutable FEE_SPLITTER;

  uint256 public immutable DEPLOYMENT_TIMESTAMP;
  uint256 public immutable BOOTSTRAP_PERIOD;
  uint256 public immutable ACCRUAL_PARAMETER;
  uint256 public immutable LP_PER_USD;

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

  constructor(BaseDeployParams memory baseParams_, DeployParams memory params_) UniswapBase(baseParams_) {
    DEPLOYMENT_TIMESTAMP = block.timestamp;

    STO = params_.STO;
    NFT = INFT(params_.NFT);

    BOOT = BaseToken(params_.BOOT);
    BLP = BaseToken(params_.BLP);
    EXIT = BaseToken(params_.EXIT);

    MASTERCHEF = params_.masterchef;
    FEE_SPLITTER = params_.feeSplitter;

    BOOTSTRAP_PERIOD = params_.bootstrapPeriod;
    ACCRUAL_PARAMETER = params_.accrualParameter * DECIMAL_PRECISION;
    LP_PER_USD = params_.lpPerUSD;

    IERC20(IUniswapV3Pool(POOL).token0()).approve(NPM, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token1()).approve(NPM, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token0()).approve(FEE_SPLITTER, MAX_UINT_256);
    IERC20(IUniswapV3Pool(POOL).token1()).approve(FEE_SPLITTER, MAX_UINT_256);
  }

  function bootstrapLock(
    AddLiquidity memory params
  ) external returns (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    require(_isBootstrapOngoing(), 'EXIT10: Bootstrap ended');

    _depositTokens(params.amount0Desired, params.amount1Desired);

    (tokenId, liquidityAdded, amountAdded0, amountAdded1) = _addLiquidity(params);

    bootstrapBucket += liquidityAdded;
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

    pendingBucket += liquidityAdded;

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

    pendingBucket -= params.liquidity;

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

    pendingBucket -= params.liquidity;

    uint256 accruedLiquidity = _getAccruedLiquidity(bond);
    boostTokenAmount = accruedLiquidity * TOKEN_MULTIPLIER;

    idToBondData[bondID].claimedBoostAmount = boostTokenAmount;
    reserveBucket += accruedLiquidity;

    uint256 remainingLiquidity = bond.bondAmount - accruedLiquidity;
    exitTokenAmount = (remainingLiquidity * TOKEN_MULTIPLIER) / LP_PER_USD;

    BLP.mint(msg.sender, boostTokenAmount);
    _mintExitCapped(msg.sender, exitTokenAmount);

    emit ConvertBond(msg.sender, bondID, bond.bondAmount, boostTokenAmount, exitTokenAmount);
  }

  function redeem(RemoveLiquidity memory params) external returns (uint256 amountRemoved0, uint256 amountRemoved1) {
    _requireValidAmount(params.liquidity);
    claimAndDistributeFees();

    reserveBucket -= params.liquidity;
    BLP.burn(msg.sender, params.liquidity * TOKEN_MULTIPLIER);

    (amountRemoved0, amountRemoved1) = _decreaseLiquidity(params);
    _collect(msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    emit Redeem(msg.sender, amountRemoved0, amountRemoved1);
  }

  function exit10() external {
    _requireOutOfTickRange();
    claimAndDistributeFees();

    inExitMode = true;

    // Stop and burn Exit rewards.
    EXIT.burn(MASTERCHEF, LP_EXIT_REWARD - MasterchefExit(MASTERCHEF).stopRewards());
    exitTokenSupplyFinal = EXIT.totalSupply();
    exitBucketFinal = uint128(_liquidityAmount() - (pendingBucket + reserveBucket));
    uint256 exitBucketRewards;

    if (POOL.token1() == TOKEN_IN) {
      (exitBucketRewards, ) = _decreaseLiquidity(
        RemoveLiquidity({ liquidity: uint128(exitBucketFinal), amount0Min: 0, amount1Min: 0, deadline: DEADLINE })
      );
      _collect(address(this), uint128(exitBucketRewards), 0);
    } else {
      (, exitBucketRewards) = _decreaseLiquidity(
        RemoveLiquidity({ liquidity: uint128(exitBucketFinal), amount0Min: 0, amount1Min: 0, deadline: DEADLINE })
      );
      _collect(address(this), 0, uint128(exitBucketRewards));
    }

    // Total initial deposits that needs to be returned to bootsrappers
    uint256 bootstrapRefund = (bootstrapBucket * exitBucketRewards) / exitBucketFinal;
    exitTokenRewardsFinal = exitBucketRewards - bootstrapRefund;
    // 30% of the exitTokenRewardsFinal goes to Bootstrappers+Team+EarlyBackers.
    uint256 tenPercent = exitTokenRewardsFinal / 10;
    // Initial deposit plus 10% of the Exit Bucket
    bootstrapRewardsPlusRefund = bootstrapRefund + tenPercent;
    // 20% of the ExitLiquidity
    teamPlusBackersRewards = tenPercent * 2;
    // 70% Exit Token holders
    exitTokenRewardsFinal -= tenPercent * 3;

    _safeTransferToken(TOKEN_OUT, STO, teamPlusBackersRewards);
  }

  function bootstrapClaim() external {
    uint256 claim = _safeTokenClaim(
      BOOT,
      IERC20(BOOT).balanceOf(msg.sender) / TOKEN_MULTIPLIER,
      bootstrapRewardsPlusRefund,
      bootstrapBucket,
      bootstrapRewardsPlusRefundClaimed
    );

    bootstrapRewardsPlusRefundClaimed += claim;

    _safeTransferToken(TOKEN_OUT, msg.sender, claim);
  }

  function exitClaim() external {
    uint256 claim = _safeTokenClaim(
      EXIT,
      IERC20(EXIT).balanceOf(msg.sender),
      exitTokenRewardsFinal,
      exitTokenSupplyFinal,
      exitTokenRewardsClaimed
    );

    exitTokenRewardsClaimed += claim;

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

    if (amountCollected0 + amountCollected1 != 0) {
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
            amountCollected0 -= amountAdded0;
            amountCollected1 -= amountAdded1;
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
    }
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
    uint256 mintAmount = newSupply > MAX_EXIT_SUPPLY ? MAX_EXIT_SUPPLY - amount : amount;
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
