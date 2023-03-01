// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IRewardDistributor {
  function updateRewards() external returns (uint256);
}
