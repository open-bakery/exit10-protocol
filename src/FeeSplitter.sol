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
    if (amountToken0 != 0) {
      ERC20(_token0()).safeTransferFrom(address(owner()), address(this), amountToken0);
      pendingBucketToken0 += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountToken0);
      remainingBucketsToken0 += _calcShare(remainingBuckets, pendingBucket + remainingBuckets, amountToken0);
    }

    if (amountToken1 != 0) {
      ERC20(_token1()).safeTransferFrom(address(owner()), address(this), amountToken1);
      pendingBucketToken1 += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountToken1);
      remainingBucketsToken1 += _calcShare(remainingBuckets, pendingBucket + remainingBuckets, amountToken1);
    }
  }

  function updateFees() external {
    _requireMasterchefCaller();

    uint256 mc0Token0 = (pendingBucketToken0 / 10) * 4;
    uint256 mc0Token1 = (pendingBucketToken1 / 10) * 4;
    uint256 mc1Token0 = remainingBucketsToken0 + (pendingBucketToken0 - mc0Token0);
    uint256 mc1Token1 = remainingBucketsToken1 + (pendingBucketToken1 - mc0Token1);

    pendingBucketToken0 = pendingBucketToken1 = 0;
    remainingBucketsToken0 = remainingBucketsToken1 = 0;

    _safeTransferTokens(MASTERCHEF_0, mc0Token0, mc0Token1);
    _safeTransferTokens(MASTERCHEF_1, mc1Token0, mc1Token1);
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

  function _safeTransferTokens(
    address _recipient,
    uint256 _amount0,
    uint256 _amount1
  ) internal {
    _safeTransferToken(_token0(), _recipient, _amount0);
    _safeTransferToken(_token1(), _recipient, _amount1);
  }

  function _safeTransferToken(
    address _token,
    address _recipient,
    uint256 _amount
  ) internal {
    if (_amount != 0) ERC20(_token).safeTransfer(_recipient, _amount);
  }

  function _getAddressUSDC() internal view returns (address usdc) {
    usdc = _compare(ERC20(_token0()).symbol(), 'USDC') ? _token0() : _token1();
  }

  function _token0() internal view returns (address) {
    return Exit10(owner()).POOL().token0();
  }

  function _token1() internal view returns (address) {
    return Exit10(owner()).POOL().token1();
  }

  function _requireMasterchefCaller() internal view {
    bool allowed = (msg.sender == MASTERCHEF_0 || msg.sender == MASTERCHEF_1);
    require(allowed, 'IFeeSplitter: Caller not allowed');
  }

  function _compare(string memory _str1, string memory _str2) internal pure returns (bool) {
    return keccak256(abi.encodePacked(_str1)) == keccak256(abi.encodePacked(_str2));
  }
}
