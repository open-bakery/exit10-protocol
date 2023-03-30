// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { AMasterchefBase } from './AMasterchefBase.sol';

contract MasterchefExit is AMasterchefBase {
  constructor(address rewardToken_, uint256 rewardsDuration_) AMasterchefBase(rewardToken_, rewardsDuration_) {}

  event UpdateRewards(address indexed caller, uint256 amount);
  event StopRewards(uint256 undistributedRewards);

  function updateRewards(uint256 amount) external override onlyOwner {
    require(amount != 0, 'MasterchefExit: Amount must not be zero');
    require(totalAllocPoint != 0, 'MasterchefExit: Must add a pool prior to adding rewards');
    require(rewardRate == 0, 'MasterchefExit: Can only deposit rewards once');
    require(IERC20(REWARD_TOKEN).balanceOf(address(this)) >= amount, 'MasterchefExit: Token balance not sufficient');
    rewardRate = (amount * PRECISION) / REWARDS_DURATION;
    periodFinish = block.timestamp + REWARDS_DURATION;
    emit UpdateRewards(msg.sender, amount);
  }

  function stopRewards(uint256 allocatedRewards) external onlyOwner returns (uint256 undistributedRewards) {
    if (block.timestamp < periodFinish) {
      unchecked {
        uint256 rewardStartTime = periodFinish - REWARDS_DURATION;
        uint256 distributedRewards = ((block.timestamp - rewardStartTime) * rewardRate) / PRECISION;
        undistributedRewards = allocatedRewards - distributedRewards;
      }
      periodFinish = block.timestamp;
    }
    emit StopRewards(undistributedRewards);
  }

  function _updateUndistributedRewards(uint256 _amount) internal override {
    _massUpdatePools();

    if (block.timestamp < periodFinish) {
      uint256 amount = _amount * PRECISION;
      uint256 duration = periodFinish - block.timestamp;
      uint256 undistributedRewards = rewardRate * duration;

      amount += undistributedRewards;
      rewardRate = amount / duration;
    }
  }
}
