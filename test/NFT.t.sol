// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { console } from 'forge-std/console.sol';
import { ABaseExit10Test } from './ABaseExit10.t.sol';

contract NFT_Test is ABaseExit10Test {
  function test_NFT() public {
    // setup: create bond for myself and alice, skip sime time to accumulate fees
    (uint256 bondId, uint256 bondAmount) = _skipBootAndCreateBond();

    console.log(nft.tokenURI(1));
  }
}
