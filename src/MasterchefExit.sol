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

    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
    rewardRate = (amount * PRECISION) / REWARDS_DURATION;

    periodFinish = block.timestamp + REWARDS_DURATION;
    isRewardDeposited = true;
  }

  function stopRewards() external onlyOwner {
    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    periodFinish = block.timestamp;
  }
}
