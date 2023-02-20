// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/IUniswapV3Pool.sol';
import './interfaces/INFT.sol';
import './interfaces/IExit10.sol';
import './utils/ChickenMath.sol';
import './BaseToken.sol';

contract Exit10 is IExit10, ChickenMath, ERC20 {
  using SafeERC20 for ERC20;

  uint256 private pendingAmount;
  uint256 private reserveAmount;
  uint256 private bootstrapAmount;

  uint256 public positionId0; // All liquidity in the pending bucket
  uint256 public positionId1; // All the liquidity excluding the pending bucket
  uint256 public totalWeightedStartTimes;
  uint256 public countChickenIn;
  uint256 public countChickenOut;

  // EXIT
  uint256 public exitTotalSupply;
  uint256 public exitLiquidity; // 70% of Exit Bucket
  uint256 public exitLiquidityClaimed;

  // BOOT
  uint256 public exitBootstrap;
  uint256 public exitBootstrapClaimed;

  // STO
  uint256 public exitTeamPlusBackers;

  mapping(uint256 => BondData) private idToBondData;
  mapping(address => uint256) public bootstrapDeposit;

  bool public inExitMode;

  // --- Constants ---
  // On Ethereum Mainnet:
  // Token0 is USDC
  // Token1 is WETH
  IUniswapV3Pool public immutable POOL;
  BaseToken public immutable BOOST;

  address public immutable STO; // STO token distribution
  address public immutable NPM; // Uniswap nonfungible position manager
  INFT public immutable NFT;

  uint256 constant MAX_UINT256 = type(uint256).max;

  int24 public immutable TICK_LOWER;
  int24 public immutable TICK_UPPER;

  uint256 public immutable MAX_SUPPLY = 10_000_000 ether;
  uint256 public immutable BOOTSTRAP_PERIOD;
  uint256 public immutable LP_PER_USD;

  // --- Accrual control variables ---
  uint256 public immutable deploymentTimestamp;
  uint256 public immutable targetAverageAgeSeconds; // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual.
  uint256 public immutable minimumAccrualParameter; // Stop adjusting `accrualParameter` when this value is reached.
  uint256 public immutable accrualAdjustmentMultiplier; // Number between 0 and 1. `accrualParameter` is multiplied by this every time there's an adjustment.
  uint256 public immutable accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds. The controller performs at most one adjustment per every period.
  uint256 public accrualParameter; // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.

  // Counts the number of adjustment periods since deployment.
  // Updated by operations that change the average outstanding bond age (createBond, chickenIn, chickenOut).
  // Used by `_calcUpdatedAccrualParameter` to tell whether it's time to perform adjustments, and if so, how many times
  // (in case the time elapsed since the last adjustment is more than one adjustment period).
  uint256 public accrualAdjustmentPeriodCount;

  // --- Events ---
  event BondCreated(address indexed bonder, uint256 bondId, uint256 amount);
  event BondClaimed(
    address indexed bonder,
    uint256 bondId,
    uint256 bondAmount,
    uint256 boostTokenClaimed,
    uint256 exitLiquidityAmount
  );
  event ExitMinted(address indexed recipient, uint256 amount);
  event BondCancelled(address indexed bonder, uint256 bondId, uint256 amountReturned0, uint256 amountReturned1);
  event TokensRedeemed(address indexed redeemer, uint256 amount0, uint256 amount1);
  event AccrualParameterUpdated(uint256 accrualParameter);

  constructor(DeployParams memory params) ERC20('Exit Liquidity', 'EXIT') {
    NPM = params.NPM;
    STO = params.STO;
    NFT = INFT(params.NFT);

    POOL = IUniswapV3Pool(params.pool);
    BOOST = new BaseToken('Boost Liquidity', 'BOOST');

    TICK_LOWER = params.tickLower;
    TICK_UPPER = params.tickUpper;

    deploymentTimestamp = block.timestamp;
    targetAverageAgeSeconds = params.targetAverageAgeSeconds;
    accrualParameter = params.initialAccrualParameter * DECIMAL_PRECISION;
    minimumAccrualParameter = params.minimumAccrualParameter * DECIMAL_PRECISION;
    require(minimumAccrualParameter != 0, 'EXIT10: Min accrual parameter cannot be zero');

    accrualAdjustmentMultiplier = 1e18 - params.accrualAdjustmentRate;
    accrualAdjustmentPeriodSeconds = params.accrualAdjustmentPeriodSeconds;

    BOOTSTRAP_PERIOD = params.bootstrapPeriod;
    LP_PER_USD = params.lpPerUSD;
  }

  function getBondData(uint256 bondID)
    external
    view
    returns (
      uint256 bondAmount,
      uint256 claimedBoostAmount,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    )
  {
    BondData memory bond = idToBondData[bondID];
    return (bond.bondAmount, bond.claimedBoostAmount, bond.startTime, bond.endTime, uint8(bond.status));
  }

  function getTreasury()
    external
    view
    returns (
      uint256 pending,
      uint256 reserve,
      uint256 exit,
      uint256 bootstrap
    )
  {
    pending = pendingAmount;
    reserve = reserveAmount;
    bootstrap = bootstrapAmount;
    exit = _exitAmount();
  }

  function calcAccruedAmount(uint256 bondID) external view returns (uint256) {
    BondData memory bond = idToBondData[bondID];

    if (bond.status != BondStatus.active) {
      return 0;
    }

    (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

    return _calcAccruedAmount(bond.startTime, bond.bondAmount, updatedAccrualParameter);
  }

  function getOpenBondCount() external view returns (uint256) {
    return NFT.totalSupply() - (countChickenIn + countChickenOut);
  }

  function bootstrapLock(address depositor, AddLiquidity memory params) external {
    require(block.timestamp < deploymentTimestamp + BOOTSTRAP_PERIOD, 'EXIT10: Bootstrap ended');

    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = _addLiquidity(
      positionId1,
      params
    );

    if (tokenId != positionId1) positionId1 = tokenId;

    bootstrapAmount += liquidityAdded;
    bootstrapDeposit[depositor] += liquidityAdded;

    _refundTokens(depositor, params.amount0Desired, amountAdded0, params.amount1Desired, amountAdded1);
  }

  function createBond(address depositor, AddLiquidity memory params) public {
    _requireNoExitMode();
    require(block.timestamp >= deploymentTimestamp + BOOTSTRAP_PERIOD, 'EXIT10: Bootstrap ongoing');

    _updateAccrualParameter();

    (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) = _addLiquidity(
      positionId0,
      params
    );

    if (tokenId != positionId0) positionId0 = tokenId;

    uint256 bondID = NFT.mint(msg.sender);

    BondData memory bondData;
    bondData.bondAmount = liquidityAdded;
    bondData.startTime = uint64(block.timestamp);
    bondData.status = BondStatus.active;
    idToBondData[bondID] = bondData;

    totalWeightedStartTimes += liquidityAdded * block.timestamp;

    _refundTokens(depositor, params.amount0Desired, amountAdded0, params.amount1Desired, amountAdded1);

    emit BondCreated(msg.sender, bondID, liquidityAdded);
  }

  function chickenOut(uint256 bondID, DecreaseLiquidity memory params) external {
    BondData memory bond = idToBondData[bondID];

    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);

    _updateAccrualParameter();

    idToBondData[bondID].status = BondStatus.chickenedOut;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    countChickenOut += 1;
    totalWeightedStartTimes -= bond.bondAmount * bond.startTime;

    (uint256 amountRemoved0, uint256 amountRemoved1) = _decreaseLiquidity(positionId0, params);
    _collect(positionId0, msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    emit BondCancelled(msg.sender, bondID, amountRemoved0, amountRemoved1);
  }

  function chickenIn(uint256 bondID, DecreaseLiquidity memory params) external {
    _requireNoExitMode();

    BondData memory bond = idToBondData[bondID];
    _requireEqualLiquidity(bond.bondAmount, params.liquidity);
    _requireCallerOwnsBond(bondID);
    _requireActiveStatus(bond.status);

    uint256 accruedBoostToken = _calcAccruedAmount(bond.startTime, bond.bondAmount, _updateAccrualParameter());
    idToBondData[bondID].status = BondStatus.chickenedIn;
    idToBondData[bondID].endTime = uint64(block.timestamp);

    countChickenIn += 1;

    // Take out of pendingPosition and add to the generalPosition
    (uint256 amountRemoved0, uint256 amountRemoved1) = _decreaseLiquidity(positionId0, params);
    _collect(positionId0, msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));
    (, uint128 addedLiquidity, , ) = _addLiquidity(
      positionId1,
      AddLiquidity({
        amount0Desired: amountRemoved0,
        amount1Desired: amountRemoved1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    //Guarantees we don't allocate more liquidity than there is due to potential slippage.
    accruedBoostToken = Math.min(accruedBoostToken, addedLiquidity);

    idToBondData[bondID].claimedBoostAmount = accruedBoostToken;
    reserveAmount += accruedBoostToken; // Increase the amount of the reserve
    totalWeightedStartTimes -= bond.bondAmount * bond.startTime;

    BOOST.mint(msg.sender, accruedBoostToken);

    // assert(bond.bondAmount > accruedbondToken); // Uncomment for tests.
    uint256 exitLiquidityIncrease = bond.bondAmount - accruedBoostToken;

    _mintExitCapped(msg.sender, (exitLiquidityIncrease * DECIMAL_PRECISION) / LP_PER_USD);

    emit BondClaimed(msg.sender, bondID, bond.bondAmount, accruedBoostToken, exitLiquidityIncrease);
  }

  function redeem(uint256 amount, DecreaseLiquidity memory params) external {
    require(amount != 0, 'EXIT10: Amount must be > 0');
    require(BOOST.balanceOf(msg.sender) >= amount, 'EXIT10: You do not own enough bond tokens');
    _requireEqualLiquidity(amount, params.liquidity);

    reserveAmount -= amount;
    BOOST.burn(msg.sender, amount);

    (uint256 amountRemoved0, uint256 amountRemoved1) = _decreaseLiquidity(positionId1, params);
    _collect(positionId1, msg.sender, uint128(amountRemoved0), uint128(amountRemoved1));

    emit TokensRedeemed(msg.sender, amountRemoved0, amountRemoved1);
  }

  function bootstrapClaim() external {
    _requireExitMode();

    uint256 amount = bootstrapDeposit[msg.sender];
    bootstrapDeposit[msg.sender] = 0;

    uint256 claim = (amount * exitBootstrap) / bootstrapAmount;
    exitBootstrapClaimed += claim;
    exitBootstrapClaimed = (exitBootstrapClaimed > exitBootstrap) ? exitBootstrap : exitBootstrapClaimed;
    // Make sure to not transfer more than the maximum reserved for Bootstrap
    ERC20(POOL.token0()).safeTransfer(msg.sender, Math.min(claim, exitBootstrap - exitBootstrapClaimed));
  }

  function exitClaim(uint256 amount) external {
    _requireExitMode();

    _burn(msg.sender, amount);
    uint256 claim = (amount * exitLiquidity) / exitTotalSupply;
    exitLiquidityClaimed += claim;
    exitLiquidityClaimed = (exitLiquidityClaimed > exitLiquidity) ? exitLiquidity : exitLiquidityClaimed;
    // Make sure to not transfer more than the maximum reserved for ExitLiquidity
    ERC20(POOL.token0()).safeTransfer(msg.sender, Math.min(claim, exitLiquidity - exitLiquidityClaimed));
  }

  function exit10() external {
    require(_currentTick() <= TICK_LOWER, 'EXIT10: Current Tick not below TICK_LOWER');

    // TODO This might be an issue since Exit is continuously minted for EXIT/USDC providers.
    // Either users will NOT receive Exit if they are late claimers or we must modify Masterchef
    // The modification would required to send all tokens to be distributed at once
    // (spread over total distribution time) but hard stop at exit10 blocktime.
    // This would allow users to claim up to that blocktime.

    exitTotalSupply = totalSupply();

    uint128 exitBucketLiquidity = uint128(_liquidityAmount(positionId1) - reserveAmount);
    (uint256 exitBucket, ) = _decreaseLiquidity(
      positionId1,
      DecreaseLiquidity({ liquidity: exitBucketLiquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp })
    );
    _collect(positionId1, address(this), uint128(exitBucket), 0);

    // Total initial deposits that needs to be returned to bootsrappers
    exitBootstrap = (bootstrapAmount * exitBucket) / exitBucketLiquidity;
    exitLiquidity = exitBucket - exitBootstrap;
    // 30% of the exitLiquidity goes to Bootstrappers+Team+EarlyBackers.
    uint256 share = exitLiquidity / 10;
    // Initial deposit plus 10% of the Exit Bucket
    exitBootstrap += share;
    // 20% of the ExitLiquidity
    exitTeamPlusBackers = share * 2;
    // 70% Exit Token holders
    exitLiquidity -= share * 3;

    ERC20(POOL.token0()).safeTransfer(STO, exitTeamPlusBackers);
  }

  function _addLiquidity(uint256 _positionId, AddLiquidity memory _params)
    internal
    returns (
      uint256 _tokenId,
      uint128 _liquidityAdded,
      uint256 _amountAdded0,
      uint256 _amountAdded1
    )
  {
    _depositTokens(_params.amount0Desired, _params.amount1Desired);

    if (_positionId == 0) {
      (_tokenId, _liquidityAdded, _amountAdded0, _amountAdded1) = INPM(NPM).mint(
        INPM.MintParams({
          token0: POOL.token0(),
          token1: POOL.token1(),
          fee: POOL.fee(),
          tickLower: TICK_LOWER, //Tick needs to exist (right spacing)
          tickUpper: TICK_UPPER, //Tick needs to exist (right spacing)
          amount0Desired: _params.amount0Desired,
          amount1Desired: _params.amount1Desired,
          amount0Min: _params.amount0Min, // slippage check
          amount1Min: _params.amount1Min, // slippage check
          recipient: address(this), // receiver of ERC721
          deadline: _params.deadline
        })
      );
    } else {
      (_liquidityAdded, _amountAdded0, _amountAdded1) = INPM(NPM).increaseLiquidity(
        INPM.IncreaseLiquidityParams({
          tokenId: _positionId,
          amount0Desired: _params.amount0Desired,
          amount1Desired: _params.amount1Desired,
          amount0Min: _params.amount0Min,
          amount1Min: _params.amount1Min,
          deadline: _params.deadline
        })
      );
      _tokenId = _positionId;
    }
  }

  function _decreaseLiquidity(uint256 _positionId, DecreaseLiquidity memory _params)
    internal
    returns (uint256 _amountRemoved0, uint256 _amountRemoved1)
  {
    (_amountRemoved0, _amountRemoved1) = INPM(NPM).decreaseLiquidity(
      INPM.DecreaseLiquidityParams({
        tokenId: _positionId,
        liquidity: _params.liquidity,
        amount0Min: _params.amount0Min,
        amount1Min: _params.amount1Min,
        deadline: _params.deadline
      })
    );
  }

  function _collectAll(address _recipient)
    internal
    returns (
      uint256 _pid0_amountCollected0,
      uint256 _pid0_amountCollected1,
      uint256 _pid1_amountCollected0,
      uint256 _pid1_amountCollected1
    )
  {
    (_pid0_amountCollected0, _pid0_amountCollected1) = _collect(
      positionId0,
      _recipient,
      type(uint128).max,
      type(uint128).max
    );
    (_pid1_amountCollected0, _pid1_amountCollected1) = _collect(
      positionId1,
      _recipient,
      type(uint128).max,
      type(uint128).max
    );
  }

  function _collect(
    uint256 _positionId,
    address _recipient,
    uint128 _amount0Max,
    uint128 _amount1Max
  ) internal returns (uint256 _amountCollected0, uint256 _amountCollected1) {
    (_amountCollected0, _amountCollected1) = INPM(NPM).collect(
      INPM.CollectParams({
        tokenId: _positionId,
        recipient: _recipient,
        amount0Max: _amount0Max,
        amount1Max: _amount1Max
      })
    );
  }

  function _depositTokens(uint256 _amount0, uint256 _amount1) internal {
    ERC20(POOL.token0()).safeTransferFrom(msg.sender, address(this), _amount0);
    ERC20(POOL.token1()).safeTransferFrom(msg.sender, address(this), _amount1);
  }

  function _refundTokens(
    address _recipient,
    uint256 _amountDesired0,
    uint256 _amountAdded0,
    uint256 _amountDesired1,
    uint256 _amountAdded1
  ) internal returns (uint256 _amountRefunded0, uint256 _amountRefunded1) {
    _amountRefunded0 = _refundToken(POOL.token0(), _recipient, _amountDesired0, _amountAdded0);
    _amountRefunded1 = _refundToken(POOL.token1(), _recipient, _amountDesired1, _amountAdded1);
  }

  function _refundToken(
    address _token,
    address _recipient,
    uint256 _amountDesired,
    uint256 _amountAdded
  ) internal returns (uint256 _amountRefunded) {
    _amountRefunded = _amountDesired - _amountAdded;
    if (_amountRefunded != 0) ERC20(_token).safeTransfer(_recipient, _amountRefunded);
  }

  function _mintExitCapped(address recipient, uint256 amount) internal {
    uint256 newSupply = totalSupply() + amount;
    uint256 mintAmount = newSupply > MAX_SUPPLY ? MAX_SUPPLY - amount : amount;
    if (mintAmount != 0) _mint(recipient, mintAmount);

    emit ExitMinted(recipient, mintAmount);
  }

  function _requireExitMode() internal view {
    require(inExitMode, 'EXIT10: Not in Exit mode');
  }

  function _requireNoExitMode() internal view {
    require(!inExitMode, 'EXIT10: In Exit mode');
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

  function _exitAmount() internal view returns (uint256) {
    return _liquidityAmount(positionId1) - (reserveAmount + bootstrapAmount);
  }

  function _liquidityAmount(uint256 _positionId) internal view returns (uint128 _liquidity) {
    (, , , , , , , _liquidity, , , , ) = INPM(NPM).positions(_positionId);
  }

  function _currentTick() internal view returns (int24 _tick) {
    (, _tick, , , , , ) = POOL.slot0();
  }

  function _calcAccruedAmount(
    uint256 _startTime,
    uint256 _capAmount,
    uint256 _accrualParameter
  ) internal view returns (uint256) {
    if (_startTime == 0) {
      return 0;
    }
    uint256 bondDuration = 1e18 * (block.timestamp - _startTime);
    uint256 accruedAmount = (_capAmount * bondDuration) / (bondDuration + _accrualParameter);
    //assert(accruedAmount < _capAmount); // we leave it as a comment so we can uncomment it for automated testing tools
    return accruedAmount;
  }

  function _updateAccrualParameter() internal returns (uint256) {
    uint256 storedAccrualParameter = accrualParameter;
    uint256 storedAccrualAdjustmentPeriodCount = accrualAdjustmentPeriodCount;

    (uint256 updatedAccrualParameter, uint256 updatedAccrualAdjustmentPeriodCount) = _calcUpdatedAccrualParameter(
      storedAccrualParameter,
      storedAccrualAdjustmentPeriodCount
    );

    if (updatedAccrualAdjustmentPeriodCount != storedAccrualAdjustmentPeriodCount) {
      accrualAdjustmentPeriodCount = updatedAccrualAdjustmentPeriodCount;

      if (updatedAccrualParameter != storedAccrualParameter) {
        accrualParameter = updatedAccrualParameter;
        emit AccrualParameterUpdated(updatedAccrualParameter);
      }
    }

    return updatedAccrualParameter;
  }

  function _calcUpdatedAccrualParameter(uint256 _storedAccrualParameter, uint256 _storedAccrualAdjustmentCount)
    internal
    view
    returns (uint256 updatedAccrualParameter, uint256 updatedAccrualAdjustmentPeriodCount)
  {
    updatedAccrualAdjustmentPeriodCount = (block.timestamp - deploymentTimestamp) / accrualAdjustmentPeriodSeconds;

    if (
      // There hasn't been enough time since the last update to warrant another update
      updatedAccrualAdjustmentPeriodCount == _storedAccrualAdjustmentCount ||
      // or `accrualParameter` is already bottomed-out
      _storedAccrualParameter == minimumAccrualParameter ||
      // or there are no outstanding bonds (avoid division by zero)
      pendingAmount == 0
    ) {
      return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
    }

    uint256 averageStartTime = totalWeightedStartTimes / pendingAmount;

    // Detailed explanation - https://github.com/liquity/ChickenBond/blob/af398985900cde68a9099a5149eca773a365e93a/LUSDChickenBonds/src/ChickenBondManager.sol#L834

    uint256 adjustmentPeriodCountWhenTargetIsExceeded = Math.ceilDiv(
      averageStartTime + targetAverageAgeSeconds - deploymentTimestamp,
      accrualAdjustmentPeriodSeconds
    );

    if (updatedAccrualAdjustmentPeriodCount < adjustmentPeriodCountWhenTargetIsExceeded) {
      // No adjustment needed; target average age hasn't been exceeded yet
      return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
    }

    uint256 numberOfAdjustments = updatedAccrualAdjustmentPeriodCount -
      Math.max(_storedAccrualAdjustmentCount, adjustmentPeriodCountWhenTargetIsExceeded - 1);

    updatedAccrualParameter = Math.max(
      (_storedAccrualParameter * decPow(accrualAdjustmentMultiplier, numberOfAdjustments)) / 1e18,
      minimumAccrualParameter
    );
  }
}
