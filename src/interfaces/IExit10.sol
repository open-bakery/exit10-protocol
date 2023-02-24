// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IExit10 {
  struct DeployParams {
    address NFT;
    address NPM;
    address STO;
    address pool;
    address masterchef0; // For STO + BOOT
    address masterchef1; // For BLP
    address masterchef2; // For EXIT/USDC
    int24 tickLower;
    int24 tickUpper;
    uint256 bootstrapPeriod; // Min duration of first chicken-in
    uint256 accrualParameter; // Initial value for `accrualParameter`
    uint256 lpPerUSD; // Amount of LP per USD that is minted on the 500 - 10000 Range Pool
  }

  /// @notice AddLiquidity Struct which is responsible for adding liquidity to a position.
  /// @dev depositor The address which the position will be credited to.

  struct AddLiquidity {
    address depositor;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct RemoveLiquidity {
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct BondData {
    uint256 bondAmount;
    uint256 claimedBoostAmount;
    uint64 startTime;
    uint64 endTime; // Timestamp of chicken in/out event
    BondStatus status;
  }

  // Valid values for `status` returned by `getBondData()`
  enum BondStatus {
    nonExistent,
    active,
    chickenedOut,
    chickenedIn
  }

  function getBondData(uint256 _bondID)
    external
    view
    returns (
      uint256 bondAmount,
      uint256 claimedBoostAmount,
      uint64 startTime,
      uint64 endTime,
      uint8 status
    );

  function getTreasury()
    external
    view
    returns (
      uint256 pending,
      uint256 reserve,
      uint256 exit,
      uint256 bootstrap
    );

  function inExitMode() external view returns (bool);
}
