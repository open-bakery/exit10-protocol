// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseTest } from './ABase.t.sol';
import { MockLido } from '../src/mocks/MockLido.sol';

contract MockLidoTest is ABaseTest {
  /// @dev
  /// Resources:
  /// https://docs.lido.fi/contracts/lido

  MockLido lido;
  uint256 depositAmount;

  function setUp() public {
    lido = new MockLido();
    depositAmount = 1 ether;
  }

  function testSubmit() public {
    uint256 shares = lido.submit{ value: depositAmount }(address(0));
    assertEq(lido.share(address(this)), depositAmount / _ratio(), 'Check shares');
    assertEq(shares, depositAmount / _ratio(), 'Check shares return');
    assertEq(lido.referral(address(this)), address(0), 'Check referral');
  }

  function testSharesOf() public {
    uint256 shares = lido.submit{ value: depositAmount }(address(0));
    assertEq(lido.sharesOf(address(this)), depositAmount / _ratio(), 'Check shares of amount');
    assertEq(lido.sharesOf(address(this)), shares, 'Check shares return');
  }

  function testTranderShares() public {
    uint256 shares = lido.submit{ value: depositAmount }(address(0));
    uint256 tokensTransferred = lido.transferShares(alice, shares / 2);
    assertEq(lido.sharesOf(address(alice)), shares / 2, 'Check shares of alice');
    assertEq(tokensTransferred, (shares / 2) * _ratio(), 'Check shares of alice');
  }

  function _ratio() internal view returns (uint256) {
    return lido.ratio();
  }
}
