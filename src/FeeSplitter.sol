// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IFeeSplitter.sol';
import './interfaces/ISwapper.sol';
import './Masterchef.sol';
import './Exit10.sol';

contract FeeSplitter {
  using SafeERC20 for ERC20;

  address immutable EXIT10;
  address immutable MASTERCHEF_0;
  address immutable MASTERCHEF_1;
  address immutable SWAPPER;

  uint256 pendingBucketTokenOut; // USDC
  uint256 pendingBucketTokenIn; // WETH
  uint256 remainingBucketsTokenOut; // USDC
  uint256 remainingBucketsTokenIn; // WETH

  constructor(
    address exit10_,
    address masterchef0_,
    address masterchef1_,
    address swapper_
  ) {
    EXIT10 = exit10_;
    MASTERCHEF_0 = masterchef0_;
    MASTERCHEF_1 = masterchef1_;
    SWAPPER = swapper_;

    ERC20(Exit10(EXIT10).TOKEN_OUT()).approve(swapper_, type(uint256).max);
  }

  modifier onlyAuthorized() {
    require(msg.sender == EXIT10, 'FeeSplitter: Caller not authorized');
    _;
  }

  function collectFees(
    uint256 pendingBucket,
    uint256 remainingBuckets,
    uint256 amountTokenOut,
    uint256 amountTokenIn
  ) external onlyAuthorized {
    if (amountTokenOut != 0) {
      ERC20(Exit10(EXIT10).TOKEN_OUT()).safeTransferFrom(EXIT10, address(this), amountTokenOut);
      pendingBucketTokenOut += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountTokenOut);
      remainingBucketsTokenOut += (amountTokenOut - pendingBucketTokenOut);
    }

    if (amountTokenIn != 0) {
      ERC20(Exit10(EXIT10).TOKEN_IN()).safeTransferFrom(EXIT10, address(this), amountTokenIn);
      pendingBucketTokenIn += _calcShare(pendingBucket, pendingBucket + remainingBuckets, amountTokenIn);
      remainingBucketsTokenIn += (amountTokenIn - pendingBucketTokenIn);
    }
  }

  function updateFees(uint256 amount) external {
    uint256 balanceTokenOut = ERC20(Exit10(EXIT10).TOKEN_OUT()).balanceOf(address(this));

    amount = Math.min(amount, balanceTokenOut);

    if (amount != 0) {
      uint256 totalExchanged = _swap(amount);

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

    _safeTransferToken(Exit10(EXIT10).TOKEN_IN(), MASTERCHEF_0, mc0TokenIn);
    _safeTransferToken(Exit10(EXIT10).TOKEN_IN(), MASTERCHEF_1, mc1TokenIn);

    Masterchef(MASTERCHEF_0).updateRewards();
    Masterchef(MASTERCHEF_1).updateRewards();
  }

  function _swap(uint256 _amount) internal returns (uint256 _acquiredEth) {
    ISwapper.SwapParameters memory params = ISwapper.SwapParameters({
      recipient: address(this),
      tokenIn: Exit10(EXIT10).TOKEN_OUT(),
      tokenOut: Exit10(EXIT10).TOKEN_IN(),
      fee: Exit10(EXIT10).FEE(),
      amountIn: _amount,
      slippage: 100,
      oracleSeconds: 60
    });

    _acquiredEth = ISwapper(SWAPPER).swap(params);
  }

  function _calcShare(
    uint256 _part,
    uint256 _total,
    uint256 _externalSum
  ) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }

  function _safeTransferToken(
    address _token,
    address _recipient,
    uint256 _amount
  ) internal {
    if (_amount != 0) ERC20(_token).safeTransfer(_recipient, _amount);
  }
}
