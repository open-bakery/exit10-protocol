// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IExit10 {
  struct DeployParams {
    address NFT;
    address STO;
    address BOOT;
    address BLP;
    address EXIT;
    address masterchef; // EXIT/USDC Stakers
    address feeSplitter; // Distribution to STO + BOOT and BLP stakers
    uint256 bootstrapPeriod; // Min duration of first chicken-in
    uint256 accrualParameter; // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.
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
