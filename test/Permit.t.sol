// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { Test } from 'forge-std/Test.sol';
import { BaseToken } from '../src/BaseToken.sol';

contract PermitTest is Test {
  address alice = vm.envAddress('ALICE_ADDRESS');
  uint256 aliceKey = vm.envUint('ALICE_KEY');

  address bob = address(0xb);
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
    _permit(aliceKey, token, owner, spender, amount, deadline);
    assertEq(token.allowance(alice, bob), amount, 'Check allowance');
  }

  // Resources:
  // https://eips.ethereum.org/EIPS/eip-191
  // https://eips.ethereum.org/EIPS/eip-712
  // https://eips.ethereum.org/EIPS/eip-2612

  function _permit(
    uint256 _privateKey,
    BaseToken _token,
    address _owner,
    address _spender,
    uint256 _value,
    uint256 _deadline
  ) internal {
    bytes32 hash = keccak256(
      abi.encodePacked(
        hex'1901',
        token.DOMAIN_SEPARATOR(),
        keccak256(
          abi.encode(
            keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
            _owner,
            _spender,
            _value,
            _token.nonces(msg.sender),
            _deadline
          )
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
    _token.permit(_owner, _spender, _value, _deadline, v, r, s);
  }
}
