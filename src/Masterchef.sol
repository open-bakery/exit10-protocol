// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './interfaces/IRewardDistributor.sol';

import 'forge-std/console.sol';

/// @title Masterchef External Rewards
/// @notice Modified masterchef contract (https://etherscan.io/address/0xc2edad668740f1aa35e4d8f227fb8e17dca888cd#code)
/// to support external rewards
contract Masterchef is Ownable {
  using SafeERC20 for IERC20;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event Claim(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  /// @notice Detail of each user.
  struct UserInfo {
    uint256 amount; // Number of tokens staked
    uint256 rewardDebt; // The amount to be discounted from future reward claims.
    //
    // At any point in time, pending user reward for a given pool is:
    // pendingReward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws a pool token:
    //   1. The pool's `accRewardPerShare` (and `lastUpdate`) gets updated.
    //   2. The pending reward is sent to the user's address.
    //   3. User's total staked `amount` gets updated.
    //   4. User's `rewardDebt` gets updated based on new staked amount.
  }

  /// @notice Detail of each pool.
  struct PoolInfo {
    address token; // Token to stake.
    uint256 allocPoint; // How many allocation points assigned to this pool.
    uint256 lastUpdateTime; // Last time that pending reward accounting happened.
    uint256 accRewardPerShare; // Accumulated rewards per share.
    uint256 totalStaked; // Total amount of tokens staked in the pool.
    uint256 accUndistributedReward; // Accumulated rewards while a pool has no stake in it.
  }

  /// @dev Division precision.
  uint256 private precision = 1e18;

  /// @notice Total allocation points. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint;

  /// @notice Time of the contract deployment.
  uint256 public timeDeployed;

  /// @notice Total rewards claimed since contract deployment.
  uint256 public totalClaimedRewards;

  /// @notice Reward token.
  address public rewardToken;

  /// @notice Address authorized to distribute the rewards.
  address public rewardDistributor;

  /// @notice Detail of each pool.
  PoolInfo[] public poolInfo;

  /// @notice Period in which the latest distribution of rewards will end.
  uint256 public periodFinish;

  /// @notice Reward rate per second. Has increased precision (when doing math with it, do div(precision))
  uint256 public rewardRate;

  ///  @notice Rewards are equaly split between the duration.
  uint256 public rewardsDuration;

  /// @notice Detail of each user who stakes tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  mapping(address => bool) private poolToken;

  modifier onlyAuthorized() {
    require(msg.sender == rewardDistributor, 'Masterchef: Caller not authorized');
    _;
  }

  constructor(address rewardToken_, uint256 rewardsDuration_) {
    rewardToken = rewardToken_;
    rewardsDuration = rewardsDuration_;
    timeDeployed = block.timestamp;
    periodFinish = timeDeployed + rewardsDuration;
  }

  function setRewardDistributor(address rd) external onlyOwner {
    require(rewardDistributor == address(0), 'Masterchef: Reward distributor already set');
    rewardDistributor = rd;
  }

  /// @notice Average reward per second generated since contract deployment.
  function avgRewardsPerSecondTotal() external view returns (uint256 avgPerSecond) {
    return totalHistoricalRewards() / (block.timestamp - timeDeployed);
  }

  /// @notice Total rewards accumulated since contract deployment.
  function totalHistoricalRewards() public view returns (uint256 rewardAmount) {
    return totalClaimedRewards + IERC20(rewardToken).balanceOf(address(this));
  }

  /// @notice Total pools.
  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  /// @notice Display user rewards for a specific pool.
  function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accRewardPerShare = pool.accRewardPerShare;

    if (pool.totalStaked != 0 && totalAllocPoint != 0) {
      accRewardPerShare += (_getPoolRewardsSinceLastUpdate(_pid) * precision) / pool.totalStaked;
    }

    return (user.amount * accRewardPerShare) / precision - user.rewardDebt;
  }

  /// @notice Add a new pool.
  function add(uint256 _allocPoint, address _token) public onlyOwner {
    require(rewardDistributor != address(0), 'Masterchef: Reward distributor not set');
    require(poolToken[address(_token)] == false, 'Masterchef: A pool already exists for this token');

    require(_token != rewardToken, 'Masterchef: Does not support staking reward token');

    totalAllocPoint = totalAllocPoint + _allocPoint;

    poolInfo.push(
      PoolInfo({
        token: _token,
        allocPoint: _allocPoint,
        lastUpdateTime: block.timestamp,
        accRewardPerShare: 0,
        totalStaked: 0,
        accUndistributedReward: 0
      })
    );

    poolToken[address(_token)] = true;
  }

  /// @notice Update the given pool's allocation point.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) public onlyOwner {
    if (_withUpdate) {
      // massUpdatePools() accounts for pending rewards from the previous allocPoint up till now.
      // If massUpdatePools() is not called, then previous allocPoint will be valid until massUpdatePools() is called.
      massUpdatePools();
    }

    totalAllocPoint -= poolInfo[_pid].allocPoint + _allocPoint;
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  /// @notice Deposit tokens to pool for reward allocation.
  function deposit(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    // Updates the accRewardPerShare and accUndistributedReward if applicable.
    _updatePool(_pid);

    uint256 pending;

    if (pool.totalStaked == 0) {
      // Special case: no one was staking, the pool was accumulating rewards.
      // All accumulated rewards are sent to the user at once.
      pending = pool.accUndistributedReward;
      pool.accUndistributedReward = 0;
    }
    if (user.amount != 0) {
      pending = _getUserPendingReward(_pid);
    }

    _claimFromPool(_pid, pending);
    _transferAmountIn(_pid, _amount);
    _updateRewardDebt(_pid);

    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw tokens from pool. Claims any rewards pending implicitly.
  function withdraw(
    uint256 _pid,
    uint256 _amount,
    bool _shouldUpdateRewards,
    uint256 _amountOut
  ) public {
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(_amount <= user.amount, 'MasterchefExternalRewards: Withdraw amount is greater than user stake.');

    _updatePool(_pid);
    _claimFromPool(_pid, _getUserPendingReward(_pid));
    _transferAmountOut(_pid, _amount);
    _updateRewardDebt(_pid);

    if (_shouldUpdateRewards) _updateRewards(_amountOut);

    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw ignoring rewards. EMERGENCY ONLY.
  // !Caution this will clear all user's pending rewards!
  function emergencyWithdraw(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    uint256 _amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;
    pool.totalStaked -= _amount;

    IERC20(pool.token).safeTransfer(address(msg.sender), _amount);
    emit EmergencyWithdraw(msg.sender, _pid, _amount);
    // No mass update dont update pending rewards
  }

  /// @notice Updates rewards for all pools by adding pending rewards.
  /// Can spend a lot of gas.
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      _updatePool(pid);
    }
  }

  /// Adds and evenly distributes rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external virtual onlyAuthorized {
    if (totalAllocPoint == 0) {
      return;
    }

    //Updates pool to account for the previous rewardRate.
    massUpdatePools();

    if (block.timestamp <= periodFinish) {
      uint256 undistributedRewards = rewardRate * (periodFinish - block.timestamp);
      rewardRate = ((undistributedRewards + amount) * precision) / rewardsDuration;
    } else {
      rewardRate = (amount * precision) / rewardsDuration;
    }

    periodFinish = block.timestamp + rewardsDuration;
  }

  function _updateRewards(uint256 _amountOut) internal {
    IRewardDistributor(rewardDistributor).updateFees(_amountOut);
  }

  /// @notice Increases accRewardPerShare and accUndistributedReward since last update.
  function _updatePool(uint256 _pid) internal {
    if (totalAllocPoint == 0) return;

    PoolInfo storage pool = poolInfo[_pid];
    uint256 poolRewards = _getPoolRewardsSinceLastUpdate(_pid);

    if (pool.totalStaked == 0) {
      pool.accRewardPerShare += poolRewards;
      pool.accUndistributedReward += poolRewards;
    } else {
      pool.accRewardPerShare += (poolRewards * precision) / pool.totalStaked;
    }

    pool.lastUpdateTime = block.timestamp;
  }

  // @notice Returns the total rewards allocated to a pool since last update.
  function _getPoolRewardsSinceLastUpdate(uint256 _pid) internal view returns (uint256 _poolRewards) {
    PoolInfo storage pool = poolInfo[_pid];

    //If reward is not updated for longer than rewardsDuration periodFinish will be < than block.timestamp
    uint256 lastTimeRewardApplicable = Math.min(block.timestamp, periodFinish);

    // If updateRewards has not been called since periodFinish
    if (pool.lastUpdateTime > lastTimeRewardApplicable) {
      return 0;
    }

    uint256 secondsElapsedSinceLastReward = lastTimeRewardApplicable - pool.lastUpdateTime;

    return (secondsElapsedSinceLastReward * rewardRate * pool.allocPoint) / totalAllocPoint / precision;
  }

  function _safeRewardTokenTransfer(address _to, uint256 _amount) internal returns (uint256 _claimed) {
    _claimed = Math.min(_amount, IERC20(rewardToken).balanceOf(address(this)));
    IERC20(rewardToken).transfer(_to, _claimed);
  }

  function withdrawStuckTokens(address _token, uint256 _amount) public onlyOwner {
    require(_token != address(rewardToken), 'MasterchefExternalRewards: Cannot withdraw reward tokens');
    require(poolToken[address(_token)] == false, 'MasterchefExternalRewards: Cannot withdraw stake tokens');
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  function _getUserPendingReward(uint256 _pid) internal view returns (uint256 _reward) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    return (user.amount * pool.accRewardPerShare) / precision - user.rewardDebt;
  }

  function _claimFromPool(uint256 _pid, uint256 _amount) internal {
    if (_amount != 0) {
      uint256 amountClaimed = _safeRewardTokenTransfer(msg.sender, _amount);
      totalClaimedRewards += amountClaimed;
      emit Claim(msg.sender, _pid, amountClaimed);
    }
  }

  function _transferAmountIn(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    if (_amount != 0) {
      IERC20(pool.token).safeTransferFrom(msg.sender, address(this), _amount);
      user.amount += _amount;
      pool.totalStaked += _amount;
    }
  }

  function _transferAmountOut(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    if (_amount != 0) {
      IERC20(pool.token).safeTransfer(msg.sender, _amount);
      user.amount -= _amount;
      pool.totalStaked -= _amount;
    }
  }

  function _updateRewardDebt(uint256 _pid) internal {
    UserInfo storage user = userInfo[_pid][msg.sender];
    user.rewardDebt = (user.amount * poolInfo[_pid].accRewardPerShare) / precision;
  }
}
