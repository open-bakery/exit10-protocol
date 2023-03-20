// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { AMasterchefBase } from './AMasterchefBase.sol';
import { IRewardDistributor } from './interfaces/IRewardDistributor.sol';

contract Masterchef is AMasterchefBase {
  using SafeERC20 for IERC20;

  /// @notice Address authorized to distribute the rewards.
  address public rewardDistributor;

  event SetRewardDistributor(address indexed caller, address indexed rewardDistributor);

  modifier onlyAuthorized() {
    require(msg.sender == rewardDistributor, 'Masterchef: Caller not authorized');
    _;
  }

  constructor(address rewardToken_, uint256 rewardsDuration_) AMasterchefBase(rewardToken_, rewardsDuration_) {}

  function setRewardDistributor(address rd) external onlyOwner {
    require(rewardDistributor == address(0), 'Masterchef: Reward distributor already set');
    rewardDistributor = rd;
    emit SetRewardDistributor(msg.sender, rd);
  }

  function withdraw(uint256 _pid, uint256 _amount, bool _shouldUpdateRewards, uint256 _amountOut) public {
    withdraw(_pid, _amount);
    if (_shouldUpdateRewards) IRewardDistributor(rewardDistributor).updateFees(_amountOut);
  }

  /// Adds and evenly distributes rewards through the rewardsDuration.
  function updateRewards(uint256 amount) external override onlyAuthorized {
    require(totalAllocPoint != 0, 'Masterchef: Must initiate a pool before updating rewards');

    IERC20(REWARD_TOKEN).safeTransferFrom(rewardDistributor, address(this), amount);
    _updateUndistributedRewards(amount);
  }
}
