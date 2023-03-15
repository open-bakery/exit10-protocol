// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IExit10 {
  struct DeployParams {
    address NFT;
    address STO;
    address BOOT;
    address BLP;
    address EXIT;
    address masterchef; // For EXIT/USDC
    address feeSplitter;
    uint256 bootstrapPeriod; // Min duration of first chicken-in
    uint256 accrualParameter; // Initial value for `accrualParameter`
    uint256 lpPerUSD; // Amount of LP per USD that is minted on the 500 - 10000 Range Pool
  }

  struct BondData {
    uint256 bondAmount;
    uint256 claimedBoostAmount;
    uint64 startTime;
    uint64 endTime;
    BondStatus status;
  }

  enum BondStatus {
    nonExistent,
    active,
    cancelled,
    converted
  }
}
