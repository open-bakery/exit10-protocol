// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { MerkleDistributor, MerkleProof, AlreadyClaimed, InvalidProof } from './MerkleDistributor.sol';
import { BaseToken } from './BaseToken.sol';
import { Exit10 } from './Exit10.sol';

contract STO is BaseToken, MerkleDistributor {
  using SafeERC20 for ERC20;

  uint256 constant MAX_SUPPLY = 300_000 ether;
  Exit10 public exit10;
  uint256 public totalAcquired;

  event SetExit10(address indexed caller, address exit10);

  constructor(bytes32 merkleRoot_) BaseToken('Share Token', 'STO') MerkleDistributor(address(this), merkleRoot_) {}

  function setExit10(address exit10_) external onlyOwner {
    require(address(exit10) == address(0), 'STO: Instance already set');
    exit10 = Exit10(exit10_);
    emit SetExit10(msg.sender, exit10_);
  }

  function claimExitLiquidity(uint256 amount) external {
    require(exit10.inExitMode(), 'STO: Not in exit mode');

    ERC20 tokenOut = ERC20(exit10.TOKEN_OUT());
    if (totalAcquired == 0) totalAcquired = tokenOut.balanceOf(address(this));

    _burn(msg.sender, amount);
    uint256 claimableToken = (amount * totalAcquired) / MAX_SUPPLY;
    tokenOut.safeTransfer(msg.sender, Math.min(claimableToken, tokenOut.balanceOf(address(this))));
  }

  function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) public override {
    if (isClaimed(index)) revert AlreadyClaimed();

    // Verify the merkle proof.
    bytes32 node = keccak256(abi.encodePacked(index, account, amount));
    if (!MerkleProof.verify(merkleProof, merkleRoot, node)) revert InvalidProof();

    // Mark it claimed and send the token.
    _setClaimed(index);
    _mint(account, amount);

    emit Claimed(index, account, amount);
  }
}
