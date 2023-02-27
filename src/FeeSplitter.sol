// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IFeeSplitter.sol';
import './Exit10.sol';

contract FeeSplitter is Ownable {
  using SafeERC20 for ERC20;

  address immutable MASTERCHEF_0;
  address immutable MASTERCHEF_1;

  uint256 pendingBucketToken0;
  uint256 pendingBucketToken1;
  uint256 remainingBucketsToken0;
  uint256 remainingBucketsToken1;

  constructor(address masterchef0, address masterchef1) {
    MASTERCHEF_0 = masterchef0;
    MASTERCHEF_1 = masterchef1;
  }

  function collectFees(
    uint256 pendingBucket,
    uint256 remainingBuckets,
    uint256 amountToken0,
    uint256 amountToken1
  ) external onlyOwner {
    Exit10 e10 = Exit10(owner());

    if (amountToken0 != 0) {
      ERC20(e10.POOL().token0()).safeTransferFrom(address(e10), address(this), amountToken0);
      pendingBucketToken0 += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountToken0);
      remainingBucketsToken0 += _calcShare(remainingBuckets, pendingBucket + remainingBuckets, amountToken0);
    }

    if (amountToken1 != 0) {
      ERC20(e10.POOL().token1()).safeTransferFrom(address(e10), address(this), amountToken1);
      pendingBucketToken1 += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountToken1);
      remainingBucketsToken1 += _calcShare(remainingBuckets, pendingBucket + remainingBuckets, amountToken1);
    }
  }

  function updateFees() external view {
    _requireMasterchefCaller();
    //
  }

  function _swapToEth(uint256 _amount) internal returns (uint256 _acquiredEth) {}

  function _calcShare(
    uint256 _part,
    uint256 _total,
    uint256 _externalSum
  ) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }

  function _requireMasterchefCaller() internal view {
    bool allowed = (msg.sender == MASTERCHEF_0 || msg.sender == MASTERCHEF_1);
    require(allowed, 'IFeeSplitter: Caller not allowed');
  }
}
