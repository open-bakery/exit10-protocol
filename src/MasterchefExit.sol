// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import 'forge-std/Test.sol';
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { AMasterchefBase } from './AMasterchefBase.sol';

contract MasterchefExit is AMasterchefBase {
  using SafeERC20 for IERC20;

  constructor(address rewardToken_, uint256 rewardsDuration_) AMasterchefBase(rewardToken_, rewardsDuration_) {}

  event UpdateRewards(address indexed caller, uint256 amount);
  event StopRewards(uint256 undistributedRewards);

  /// @notice Updates rewardRate.
  /// Adds and evenly distributes rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external override onlyOwner {
    require(amount != 0, 'MasterchefExit: Amount must not be zero');
    require(totalAllocPoint != 0, 'MasterchefExit: Must add a pool prior to adding rewards');
    require(rewardRate == 0, 'MasterchefExit: Can only deposit rewards once');
    require(IERC20(REWARD_TOKEN).balanceOf(address(this)) >= amount, 'MasterchefExit: Token balance not sufficient');
    rewardRate = (amount * PRECISION) / REWARDS_DURATION;
    periodFinish = block.timestamp + REWARDS_DURATION;
    emit UpdateRewards(msg.sender, amount);
  }

  function stopRewards(uint256 allocatedRewards) external onlyOwner returns (uint256 remainingRewards) {
    if (block.timestamp < periodFinish) {
      uint256 undistributedRewards = ((block.timestamp - (periodFinish - REWARDS_DURATION)) * rewardRate) / PRECISION;
      remainingRewards = allocatedRewards - undistributedRewards;
      periodFinish = block.timestamp;
      emit StopRewards(undistributedRewards);
    } else emit StopRewards(0);
  }
}
