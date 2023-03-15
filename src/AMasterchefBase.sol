// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract AMasterchefBase is Ownable {
  using SafeERC20 for IERC20;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event Claim(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  struct PoolInfo {
    address token;
    uint256 allocPoint;
    uint256 lastUpdateTime;
    uint256 totalStaked;
    uint256 accRewardPerShare;
    uint256 accUndistributedReward;
  }

  uint256 public constant PRECISION = 1e20;
  uint256 public immutable REWARDS_DURATION;
  address public immutable REWARD_TOKEN;

  uint256 public totalAllocPoint;
  uint256 public totalClaimedRewards;
  uint256 public rewardRate;
  uint256 public periodFinish;

  PoolInfo[] public poolInfo;
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  mapping(address => bool) private poolToken;

  constructor(address rewardToken_, uint256 rewardsDuration_) {
    REWARD_TOKEN = rewardToken_;
    REWARDS_DURATION = rewardsDuration_;
    periodFinish = block.timestamp + rewardsDuration_;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

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

  function add(uint256 _allocPoint, address _token) external onlyOwner {
    require(poolToken[address(_token)] == false, 'Masterchef: Token already added');
    require(_token != REWARD_TOKEN, 'Masterchef: Staking reward token not supported');
    require(_allocPoint != 0, 'Masterchef: Allocation must be non zero');

    if (totalAllocPoint != 0) _massUpdatePools();

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

  function deposit(uint256 _pid, uint256 _amount) external {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    // Updates the accRewardPerShare and accUndistributedReward if applicable.
    _updatePool(_pid);

    if (pool.totalStaked == 0) {
      // Special case: no one was staking, the pool was accumulating rewards.
      _updateUndistributedRewards(pool.accUndistributedReward);
      pool.accUndistributedReward = 0;
    } else {
      _safeClaimRewards(_pid, _getUserPendingReward(user.amount, user.rewardDebt, pool.accRewardPerShare));
    }

    _transferAmountIn(pool.token, _amount);
    user.amount += _amount;
    user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
    pool.totalStaked += _amount;

    emit Deposit(msg.sender, _pid, _amount);
  }

  function withdraw(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    _updatePool(_pid);

    _amount = _amount > user.amount ? user.amount : _amount;

    _safeClaimRewards(_pid, _getUserPendingReward(user.amount, user.rewardDebt, pool.accRewardPerShare));

    user.amount -= _amount;
    user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
    pool.totalStaked -= _amount;
    _transferAmountOut(pool.token, _amount);

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

  /// @notice Updates rewardRate.
  /// Must add and evenly distribute rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external virtual onlyOwner {
    require(totalAllocPoint != 0, 'Masterchef: Must initiate a pool before updating rewards');

    IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

    _updateUndistributedRewards(amount);
  }

  function _updateUndistributedRewards(uint256 _amount) internal virtual {
    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    if (block.timestamp < periodFinish) {
      uint256 undistributedRewards = rewardRate * (periodFinish - block.timestamp);
      rewardRate = (undistributedRewards + _amount * PRECISION) / REWARDS_DURATION;
    } else {
      rewardRate = (_amount * PRECISION) / REWARDS_DURATION;
    }

    periodFinish = block.timestamp + REWARDS_DURATION;
  }

  /// @notice Increases accRewardPerShare and accUndistributedReward since last update.
  // Every time there is an update on *stake amount* we should update THE pool.
  function _updatePool(uint256 _pid) internal {
    PoolInfo storage pool = poolInfo[_pid];

    uint256 poolRewards = _getPoolRewardsSinceLastUpdate(pool.lastUpdateTime, pool.allocPoint);

    if (poolRewards != 0) {
      if (pool.totalStaked == 0) {
        pool.accUndistributedReward += poolRewards;
      } else {
        pool.accRewardPerShare += (poolRewards * PRECISION) / pool.totalStaked;
      }
    }

    pool.lastUpdateTime = block.timestamp;
  }

  // @notice Returns the total rewards allocated to a pool since last update.
  function _getPoolRewardsSinceLastUpdate(
    uint256 _poolLastUpdateTime,
    uint256 _poolAllocPoint
  ) internal view returns (uint256 _poolRewards) {
    // If _updatePool has not been called since periodFinish
    if (_poolLastUpdateTime > periodFinish) return 0;

    //If reward is not updated for longer than rewardsDuration periodFinish will be < than block.timestamp
    uint256 lastTimeRewardApplicable = Math.min(block.timestamp, periodFinish);

    return
      ((lastTimeRewardApplicable - _poolLastUpdateTime) * rewardRate * _poolAllocPoint) / totalAllocPoint / PRECISION;
  }

  /// @notice Increases accRewardPerShare and accUndistributedReward for all pools since last update up to block.timestamp.
  /// Every time there is an update on *rewardRate* or *totalAllocPoint* we should update ALL pools.
  function _massUpdatePools() internal {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      _updatePool(pid);
    }
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
