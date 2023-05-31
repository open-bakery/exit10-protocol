// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ILido } from '../interfaces/ILido.sol';

contract MockLido is ILido {
  mapping(address => address) public referral;
  mapping(address => uint256) public share;
  uint256 public ratio = 2;

  function submit(address _referral) external payable returns (uint256) {
    uint shareAmount = msg.value / ratio;
    share[msg.sender] += shareAmount;
    referral[msg.sender] = _referral;
    return shareAmount;
  }

  function sharesOf(address account) external view returns (uint256) {
    return share[account];
  }

  function transferShares(address recipient, uint256 sharesAmount) external returns (uint256 tokens) {
    require(share[msg.sender] >= sharesAmount, 'MockLido: Insufficient Shares');
    share[msg.sender] -= sharesAmount;
    share[recipient] += sharesAmount;
    return sharesAmount * ratio;
  }
}
