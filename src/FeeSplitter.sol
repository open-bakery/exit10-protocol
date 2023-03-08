// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IFeeSplitter.sol';
import './interfaces/ISwapper.sol';
import './Masterchef.sol';
import './Exit10.sol';

contract FeeSplitter is Ownable {
  using SafeERC20 for ERC20;

  address immutable MASTERCHEF_0;
  address immutable MASTERCHEF_1;
  address immutable SWAPPER;

  address public exit10;

  uint256 public pendingBucketTokenOut; // USDC
  uint256 public pendingBucketTokenIn; // WETH
  uint256 public remainingBucketsTokenOut; // USDC
  uint256 public remainingBucketsTokenIn; // WETH

  constructor(
    address masterchef0_,
    address masterchef1_,
    address swapper_
  ) {
    MASTERCHEF_0 = masterchef0_;
    MASTERCHEF_1 = masterchef1_;
    SWAPPER = swapper_;
  }

  modifier onlyAuthorized() {
    require(msg.sender == exit10, 'FeeSplitter: Caller not authorized');
    _;
  }

  function setExit10(address exit10_) external onlyOwner {
    exit10 = exit10_;
    ERC20(Exit10(exit10).TOKEN_OUT()).approve(SWAPPER, type(uint256).max);
    ERC20(Exit10(exit10).TOKEN_IN()).approve(MASTERCHEF_0, type(uint256).max);
    ERC20(Exit10(exit10).TOKEN_IN()).approve(MASTERCHEF_1, type(uint256).max);
    renounceOwnership();
  }

  function collectFees(
    uint256 pendingBucket,
    uint256 remainingBuckets,
    uint256 amountTokenOut,
    uint256 amountTokenIn
  ) external onlyAuthorized {
    if (amountTokenOut != 0) {
      ERC20(Exit10(exit10).TOKEN_OUT()).safeTransferFrom(exit10, address(this), amountTokenOut);
      pendingBucketTokenOut += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountTokenOut);
      remainingBucketsTokenOut += (amountTokenOut - pendingBucketTokenOut);
    }

    if (amountTokenIn != 0) {
      ERC20(Exit10(exit10).TOKEN_IN()).safeTransferFrom(exit10, address(this), amountTokenIn);
      pendingBucketTokenIn += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountTokenIn);
      remainingBucketsTokenIn += (amountTokenIn - pendingBucketTokenIn);
    }
  }

  function updateFees(uint256 amount) external returns (uint256 totalExchanged) {
    uint256 balanceTokenOut = ERC20(Exit10(exit10).TOKEN_OUT()).balanceOf(address(this));

    amount = Math.min(amount, balanceTokenOut);

    if (amount != 0) {
      totalExchanged = _swap(amount);

      uint256 notExchanged;
      uint256 notExchangedPendingShare;

      if (amount != balanceTokenOut) {
        notExchanged = balanceTokenOut - amount;
        notExchangedPendingShare = _calcShare(
          pendingBucketTokenOut,
          pendingBucketTokenOut + remainingBucketsTokenOut,
          notExchanged
        );
      }

      uint256 exchangedPendingShare = _calcShare(
        pendingBucketTokenOut,
        pendingBucketTokenOut + remainingBucketsTokenOut,
        totalExchanged
      );

      pendingBucketTokenIn += exchangedPendingShare;
      remainingBucketsTokenIn += (totalExchanged - exchangedPendingShare);

      pendingBucketTokenOut = notExchangedPendingShare;
      remainingBucketsTokenOut = notExchanged - notExchangedPendingShare;
    }

    uint256 mc0TokenIn = (pendingBucketTokenIn / 10) * 4;
    uint256 mc1TokenIn = remainingBucketsTokenIn + (pendingBucketTokenIn - mc0TokenIn);

    pendingBucketTokenIn = 0;
    remainingBucketsTokenIn = 0;

    Masterchef(MASTERCHEF_0).updateRewards(mc0TokenIn);
    Masterchef(MASTERCHEF_1).updateRewards(mc1TokenIn);
  }

  function _swap(uint256 _amount) internal returns (uint256 _acquiredEth) {
    ISwapper.SwapParameters memory params = ISwapper.SwapParameters({
      recipient: address(this),
      tokenIn: Exit10(exit10).TOKEN_OUT(),
      tokenOut: Exit10(exit10).TOKEN_IN(),
      fee: Exit10(exit10).FEE(),
      amountIn: _amount,
      slippage: 1000,
      oracleSeconds: 60
    });

    _acquiredEth = ISwapper(SWAPPER).swap(params);
  }

  function _safeTransferToken(
    address _token,
    address _recipient,
    uint256 _amount
  ) internal {
    if (_amount != 0) ERC20(_token).safeTransfer(_recipient, _amount);
  }

  function _calcShare(
    uint256 _part,
    uint256 _total,
    uint256 _externalSum
  ) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }
}
