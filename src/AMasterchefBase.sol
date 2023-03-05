// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import 'forge-std/Test.sol';

abstract contract AMasterchefBase is Ownable {
  using SafeERC20 for IERC20;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event Claim(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  /// @notice Detail of each user.
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  /// @notice Detail of each pool.
  struct PoolInfo {
    address token; // Token to stake.
    uint256 allocPoint; // How many allocation points assigned to this pool.
    uint256 lastUpdateTime; // Last time that pending reward accounting happened.
    uint256 totalStaked; // Total amount of tokens staked in the pool.
    uint256 accRewardPerShare; // Accumulated rewards per share.
    uint256 accUndistributedReward; // Accumulated rewards while a pool has no stake in it.
  }

  /// @dev Division PRECISION.
  uint256 internal constant PRECISION = 1e20;

  ///  @notice Rewards are equaly split between the duration.
  uint256 public immutable REWARDS_DURATION;

  /// @notice Reward token.
  address public immutable REWARD_TOKEN;

  /// @notice Total allocation points. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint;

  /// @notice Total rewards claimed since contract deployment.
  uint256 public totalClaimedRewards;

  /// @notice Period in which the latest distribution of rewards will end.
  uint256 public periodFinish;

  /// @notice Reward rate per second. Has increased PRECISION (when doing math with it, do div(PRECISION))
  uint256 public rewardRate;

  /// @notice Detail of each pool.
  PoolInfo[] public poolInfo;

  /// @notice Detail of each user who stakes tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  mapping(address => bool) private poolToken;

  constructor(address rewardToken_, uint256 rewardsDuration_) {
    REWARD_TOKEN = rewardToken_;
    REWARDS_DURATION = rewardsDuration_;
    periodFinish = block.timestamp + rewardsDuration_;
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
      accRewardPerShare +=
        (_getPoolRewardsSinceLastUpdate(pool.lastUpdateTime, pool.allocPoint) * PRECISION) /
        pool.totalStaked;
    }

    return (user.amount * accRewardPerShare) / PRECISION - user.rewardDebt;
  }

  /// @notice Add a new pool.
  function add(uint256 _allocPoint, address _token) external onlyOwner {
    require(poolToken[address(_token)] == false, 'Masterchef: A pool already exists for this token');
    require(_token != REWARD_TOKEN, 'Masterchef: Does not support staking reward token');

    _massUpdatePools();

    totalAllocPoint += _allocPoint;

    poolInfo.push(
      PoolInfo({
        token: _token,
        allocPoint: _allocPoint,
        lastUpdateTime: block.timestamp,
        totalStaked: 0,
        accRewardPerShare: 0,
        accUndistributedReward: 0
      })
    );

    poolToken[address(_token)] = true;
  }

  /// @notice Update the given pool's allocation point.
  function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {
    _massUpdatePools();

    totalAllocPoint -= poolInfo[_pid].allocPoint + _allocPoint;
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  /// @notice Deposit tokens to pool for reward allocation. Claims any rewards pending from the pool
  function deposit(uint256 _pid, uint256 _amount) external {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    _transferAmountIn(pool.token, _amount);

    // Updates the accRewardPerShare and accUndistributedReward if applicable.
    _updatePool(_pid);

    uint256 pending;

    if (pool.totalStaked == 0) {
      // Special case: no one was staking, the pool was accumulating rewards.
      // All accumulated rewards are sent to the user at once.
      pending = pool.accUndistributedReward;
      pool.accUndistributedReward = 0;
    } else {
      if (user.amount != 0) {
        pending = _getUserPendingReward(user.amount, user.rewardDebt, pool.accRewardPerShare);
      }
    }

    user.amount += _amount;
    user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
    pool.totalStaked += _amount;

    _safeClaimRewards(_pid, pending);

    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw tokens from pool. Claims any rewards pending implicitly.
  function withdraw(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    _amount = _amount > user.amount ? user.amount : _amount;

    _updatePool(_pid);

    uint256 pendingRewards = _getUserPendingReward(user.amount, user.rewardDebt, pool.accRewardPerShare);

    user.amount -= _amount;
    user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
    pool.totalStaked -= _amount;

    _transferAmountOut(pool.token, _amount);
    _safeClaimRewards(_pid, pendingRewards);

    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw ignoring rewards. EMERGENCY ONLY.
  // !Caution this will clear all user's pending rewards!
  function emergencyWithdraw(uint256 _pid) external {
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

  function withdrawStuckTokens(address _token, uint256 _amount) external onlyOwner {
    require(_token != address(REWARD_TOKEN), 'Masterchef: Cannot withdraw reward tokens');
    require(poolToken[address(_token)] == false, 'Masterchef: Cannot withdraw stake tokens');
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  /// @notice Updates rewardRate.
  /// Must add and evenly distribute rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external virtual onlyOwner {
    require(totalAllocPoint != 0, 'Masterchef: Must initiate a pool before updating rewards');

    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

    if (block.timestamp <= periodFinish) {
      uint256 undistributedRewards = rewardRate * (periodFinish - block.timestamp);
      rewardRate = ((undistributedRewards + amount) * PRECISION) / REWARDS_DURATION;
    } else {
      rewardRate = (amount * PRECISION) / REWARDS_DURATION;
    }

    periodFinish = block.timestamp + REWARDS_DURATION;
  }

  /// @notice Increases accRewardPerShare and accUndistributedReward for all pools since last update up to block.timestamp.
  /// Every time there is an update on *rewardRate* or *totalAllocPoint* we should update ALL pools.
  function _massUpdatePools() internal {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      _updatePool(pid);
    }
  }

  /// @notice Increases accRewardPerShare and accUndistributedReward since last update.
  // Every time there is an update on *stake amount* we should update THE pool.
  function _updatePool(uint256 _pid) internal {
    if (totalAllocPoint == 0) return;

    PoolInfo storage pool = poolInfo[_pid];

    uint256 poolRewards = _getPoolRewardsSinceLastUpdate(pool.lastUpdateTime, pool.allocPoint);

    if (poolRewards != 0) {
      if (pool.totalStaked == 0) {
        pool.accRewardPerShare += poolRewards;
        pool.accUndistributedReward += poolRewards;
      } else {
        pool.accRewardPerShare += (poolRewards * PRECISION) / pool.totalStaked;
      }
    }

    pool.lastUpdateTime = block.timestamp;
  }

  // @notice Returns the total rewards allocated to a pool since last update.
  function _getPoolRewardsSinceLastUpdate(uint256 _poolLastUpdateTime, uint256 _poolAllocPoint)
    internal
    view
    returns (uint256 _poolRewards)
  {
    // If _updatePool has not been called since periodFinish
    if (_poolLastUpdateTime > periodFinish) return 0;

    //If reward is not updated for longer than rewardsDuration periodFinish will be < than block.timestamp
    uint256 lastTimeRewardApplicable = Math.min(block.timestamp, periodFinish);

    return
      ((lastTimeRewardApplicable - _poolLastUpdateTime) * rewardRate * _poolAllocPoint) / totalAllocPoint / PRECISION;
  }

  function _safeClaimRewards(uint256 _pid, uint256 _amount) internal {
    if (_amount != 0) {
      uint256 _claimable = Math.min(_amount, IERC20(REWARD_TOKEN).balanceOf(address(this)));
      totalClaimedRewards += _claimable;
      IERC20(REWARD_TOKEN).safeTransfer(msg.sender, _claimable);
      emit Claim(msg.sender, _pid, _claimable);
    }
  }

  function _transferAmountIn(address _token, uint256 _amount) internal {
    if (_amount != 0) IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  function _transferAmountOut(address _token, uint256 _amount) internal {
    if (_amount != 0) IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  function _getUserPendingReward(
    uint256 _userAmount,
    uint256 _userDebt,
    uint256 _poolAccRewardPerShare
  ) internal pure returns (uint256 _reward) {
    return (_userAmount * _poolAccRewardPerShare) / PRECISION - _userDebt;
  }
}
