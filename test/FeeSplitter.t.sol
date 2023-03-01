// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import '../src/BaseToken.sol';
import '../src/FeeSplitter.sol';
import '../src/Masterchef.sol';

contract Exit10Mock is Test {
  constructor(
    address spender_,
    address USDC_,
    address WETH_
  ) {
    ERC20(USDC_).approve(spender_, type(uint256).max);
    ERC20(WETH_).approve(spender_, type(uint256).max);
  }
}

contract FeeSplitterTest is Test {
  BaseToken STO = new BaseToken('Share Token', 'STO');
  BaseToken BOOT = new BaseToken('Bootstrap Token', 'BOOT');
  BaseToken BLP = new BaseToken('Boosted LP', 'BLP');

  address USDC = vm.envAddress('USDC');
  address WETH = vm.envAddress('WETH');

  address masterchef0 = address(new Masterchef(WETH, 2 weeks));
  address masterchef1 = address(new Masterchef(WETH, 2 weeks));
  uint256 initialBalance = 1_000 ether;
  Exit10Mock exit10;
  FeeSplitter feeSplitter;

  function setUp() public {
    feeSplitter = new FeeSplitter(masterchef0, masterchef1, address(0xabc));
    Masterchef(masterchef0).setRewardDistributor(address(feeSplitter));
    Masterchef(masterchef1).setRewardDistributor(address(feeSplitter));

    exit10 = new Exit10Mock(address(feeSplitter), USDC, WETH);

    deal(USDC, address(exit10), initialBalance);
    deal(WETH, address(exit10), initialBalance);
  }
}
