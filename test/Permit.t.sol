// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import '../src/BaseToken.sol';

contract PermitTest is Test {
  address alice = vm.envAddress('PUBLIC_KEY_ANVIL');
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
    uint256 sk = vm.envUint('PRIVATE_KEY_ANVIL');
    _permit(sk, token, owner, spender, amount, deadline);
    assertTrue(token.allowance(alice, bob) == 100 ether, 'Check allowance');
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
