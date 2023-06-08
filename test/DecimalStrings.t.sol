// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { DecimalStrings } from '../src/libraries/DecimalStrings.sol';

contract DecimalStringsTest is Test {
  uint256 number;

  function setUp() public {
    number = 54535400000000000;
  }

  function testDecimalStrings() public view {
    console.log(DecimalStrings.decimalString(number, 18, false));
  }
}
