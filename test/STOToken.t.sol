// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { STOToken } from '../src/STOToken.sol';
import { ABaseTest } from './ABase.t.sol';

contract STOTokenTest is ABaseTest {
  STOToken sto;
  bytes32 MERKLE_ROOT = vm.envBytes32('STO_MERKLE_ROOT');
  bytes32[] aliceProof;
  bytes32[] wrongProof;
  uint256 aliceIndex = 1;
  uint256 differentIndex = 2;
  uint256 aliceAmount = 1500 ether;
  uint256 wrongAmount = 1499 ether;

  function setUp() public {
    sto = new STOToken(MERKLE_ROOT);
    alice = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    aliceProof.push(bytes32(0x9655a6d65c6762eea5b2e5260d80b3c4b1a8c6d8cfc7dff11660bdb843a44e65));
    aliceProof.push(bytes32(0xfdb745237107b4162793f19ebe126d995cf40d8cdbf5f14e9637d8034328ff6e));
    wrongProof.push(bytes32(0x9555a6d65c6762eea5b2e5260d80b3c4b1a8c6d8cfc7dff11660bdb843a44e65)); // changed one digit
    wrongProof.push(bytes32(0xfdb745237107b4162793f19ebe126d995cf40d8cdbf5f14e9637d8034328ff6e));
  }

  function test_claim() public {
    vm.startPrank(alice);
    uint256 balanceBefore = _balance(sto, alice);
    sto.claim(aliceIndex, alice, aliceAmount, aliceProof);
    assertEq(_balance(sto, alice), balanceBefore + aliceAmount);
    assertTrue(sto.isClaimed(aliceIndex));
    assertTrue(!sto.isClaimed(differentIndex));
    vm.stopPrank();
  }

  // the proofs are public so this is a valid case
  function test_claim_ForSomeoneElse() public {
    vm.startPrank(bob);
    uint256 balanceBefore = _balance(sto, alice);
    sto.claim(aliceIndex, alice, aliceAmount, aliceProof);
    assertEq(_balance(sto, alice), balanceBefore + aliceAmount);
    assertTrue(sto.isClaimed(aliceIndex));
    assertTrue(!sto.isClaimed(differentIndex));
    vm.stopPrank();
  }

  function test_claim_revertIf_AlreadyClaimed() public {
    vm.startPrank(alice);
    sto.claim(aliceIndex, alice, aliceAmount, aliceProof);
    vm.expectRevert();
    sto.claim(aliceIndex, alice, aliceAmount, aliceProof);
    vm.stopPrank();
  }

  function test_claim_revertIf_WrongIndex() public {
    vm.expectRevert();
    vm.prank(alice);
    sto.claim(differentIndex, alice, aliceAmount, aliceProof);
  }

  function test_claim_revertIf_WrongAccount() public {
    vm.expectRevert();
    vm.prank(bob);
    sto.claim(aliceIndex, bob, wrongAmount, aliceProof);
  }

  function test_claim_revertIf_WrongAmount() public {
    vm.expectRevert();
    vm.prank(alice);
    sto.claim(aliceIndex, alice, wrongAmount, aliceProof);
  }

  function test_claim_revertIf_WrongProof() public {
    vm.expectRevert();
    vm.prank(alice);
    sto.claim(aliceIndex, alice, aliceAmount, wrongProof);
  }
}
