// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './AMasterchefBase.sol';

contract MasterchefExit is AMasterchefBase {
  using SafeERC20 for IERC20;

  bool isRewardDeposited;

  constructor(address rewardToken_, uint256 rewardsDuration_) AMasterchefBase(rewardToken_, rewardsDuration_) {}

  /// @notice Updates rewardRate.
  /// Adds and evenly distributes rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external override onlyOwner {
    require(totalAllocPoint != 0, 'MasterchefExit: Must add a pool prior to adding rewards');
    require(!isRewardDeposited, 'MasterchefExit: Can only deposit rewards once');

    IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
    _updateUndistributedRewards(amount);
    isRewardDeposited = true;
  }

  function _updateUndistributedRewards(uint256 _amount) internal virtual override {
    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    if (!isRewardDeposited) {
      rewardRate = (_amount * PRECISION) / REWARDS_DURATION;
      periodFinish = block.timestamp + REWARDS_DURATION;
    } else {
      if (block.timestamp < periodFinish) {
        uint256 remainingTime = periodFinish - block.timestamp;
        uint256 undistributedRewards = rewardRate * remainingTime;
        rewardRate = (undistributedRewards + _amount) / remainingTime;
      }
    }
  }

  function stopRewards() external onlyOwner {
    periodFinish = block.timestamp;
  }
}
