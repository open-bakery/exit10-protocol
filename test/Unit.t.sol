// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';

contract UnitTest is Test {
  function setUp() public {}

  function testFuzz_calculateShare(uint128 part, uint128 total, uint128 externalSum) public {
    _calcShare(part, total, externalSum);
  }

  function _calcShare(uint256 _part, uint256 _total, uint256 _externalSum) internal pure returns (uint256 _share) {
    if (_total != 0) _share = (_part * _externalSum) / _total;
  }
}
