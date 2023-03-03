// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './MasterchefBase.sol';
import './interfaces/IRewardDistributor.sol';

/// @title Masterchef External Rewards
/// @notice Modified masterchef contract (https://etherscan.io/address/0xc2edad668740f1aa35e4d8f227fb8e17dca888cd#code)
/// to support external rewards
contract Masterchef is MasterchefBase {
  using SafeERC20 for IERC20;

  /// @notice Address authorized to distribute the rewards.
  address public rewardDistributor;

  modifier onlyAuthorized() {
    require(msg.sender == rewardDistributor, 'Masterchef: Caller not authorized');
    _;
  }

  constructor(address rewardToken_, uint256 rewardsDuration_) MasterchefBase(rewardToken_, rewardsDuration_) {}

  function setRewardDistributor(address rd) external onlyOwner {
    require(rewardDistributor == address(0), 'Masterchef: Reward distributor already set');
    rewardDistributor = rd;
  }

  function withdraw(
    uint256 _pid,
    uint256 _amount,
    bool _shouldUpdateRewards,
    uint256 _amountOut
  ) public {
    withdraw(_pid, _amount);
    if (_shouldUpdateRewards) _updateRewards(_amountOut);
  }

  /// Adds and evenly distributes rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external virtual override onlyAuthorized {
    require(totalAllocPoint != 0, 'Masterchef: Must initiate a pool before updating rewards');

    //Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    IERC20(REWARD_TOKEN).safeTransferFrom(rewardDistributor, address(this), amount);

    if (block.timestamp <= periodFinish) {
      uint256 undistributedRewards = rewardRate * (periodFinish - block.timestamp);
      rewardRate = ((undistributedRewards + amount) * PRECISION) / REWARDS_DURATION;
    } else {
      rewardRate = (amount * PRECISION) / REWARDS_DURATION;
    }

    periodFinish = block.timestamp + REWARDS_DURATION;
  }

  function _updateRewards(uint256 _amountOut) internal {
    IRewardDistributor(rewardDistributor).updateFees(_amountOut);
  }
}
