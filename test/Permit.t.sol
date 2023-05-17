// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ABaseTest, BaseToken } from './ABase.t.sol';

contract PermitTest is ABaseTest {
  /// @dev
  /// Resources:
  /// https://eips.ethereum.org/EIPS/eip-191
  /// https://eips.ethereum.org/EIPS/eip-712
  /// https://eips.ethereum.org/EIPS/eip-2612

  BaseToken token;

  function setUp() public {
    token = new BaseToken('Token', 'TKN');
    token.mint(alice, 100 ether);
  }

  function testPermit() public {
    address owner = alice;
    address spender = bob;
    uint256 amount = 100 ether;
    uint256 deadline = block.timestamp;
    PermitParameters memory _params = _getPermitParams(alicePK, address(token), owner, spender, amount, deadline);
    BaseToken(_params.token).permit(
      _params.owner,
      _params.spender,
      _params.value,
      _params.deadline,
      _params.v,
      _params.r,
      _params.s
    );
    assertEq(token.allowance(alice, bob), amount, 'Check allowance');
  }
}
