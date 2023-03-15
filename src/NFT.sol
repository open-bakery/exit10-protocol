// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { ERC721, ERC721Enumerable } from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

import { IExit10 } from './interfaces/IExit10.sol';

contract NFT is ERC721Enumerable, Ownable {
  IExit10 public exit10;
  uint256 public immutable TRANSFER_LOCKOUT_PERIOD_SECONDS;

  modifier onlyAuthorized() {
    require(msg.sender == address(exit10), 'NFT: Caller must be Exit10');
    _;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 transferLockoutPeriodSeconds_
  ) ERC721(name_, symbol_) {
    TRANSFER_LOCKOUT_PERIOD_SECONDS = transferLockoutPeriodSeconds_;
  }

  function setExit10(address _exit10) external onlyOwner {
    require(_exit10 != address(0), 'NFT: _exit10 must be non-zero');
    exit10 = IExit10(_exit10);
    renounceOwnership();
  }

  function mint(address _bonder) external onlyAuthorized returns (uint256 tokenID) {
    // We actually increase totalSupply in `ERC721Enumerable._beforeTokenTransfer` when we `_mint`.
    tokenID = totalSupply() + 1;
    _mint(_bonder, tokenID);
  }

  function tokenURI(uint256 _tokenID) public view override returns (string memory) {
    require(_exists(_tokenID), 'NFT: URI query for nonexistent token');
    return ('uri');
  }

  function getBondAmount(uint256 _tokenID) external view returns (uint256 tokenAmount) {
    (tokenAmount, , , , ) = exit10.getBondData(_tokenID);
  }

  function getBondClaimed(uint256 _tokenID) external view returns (uint256 claimedBoostedToken) {
    (, claimedBoostedToken, , , ) = exit10.getBondData(_tokenID);
  }

  function getBondStartTime(uint256 _tokenID) external view returns (uint256 startTime) {
    (, , startTime, , ) = exit10.getBondData(_tokenID);
  }

  function getBondEndTime(uint256 _tokenID) external view returns (uint256 endTime) {
    (, , , endTime, ) = exit10.getBondData(_tokenID);
  }

  function getBondStatus(uint256 _tokenID) external view returns (uint8 status) {
    (, , , , status) = exit10.getBondData(_tokenID);
  }

  // Prevent transfers for a period of time after chickening in or out
  function _beforeTokenTransfer(address _from, address _to, uint256 _tokenID, uint256 _batchSize) internal override {
    if (_from != address(0)) {
      (, , , uint256 endTime, uint8 status) = exit10.getBondData(_tokenID);

      require(
        status == uint8(IExit10.BondStatus.active) || block.timestamp >= endTime + TRANSFER_LOCKOUT_PERIOD_SECONDS,
        'NFT: Cannot transfer during lockout period'
      );
    }

    super._beforeTokenTransfer(_from, _to, _tokenID, _batchSize);
  }
}
