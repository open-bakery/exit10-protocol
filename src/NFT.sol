// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './interfaces/IExit10.sol';

//import "forge-std/console.sol";

contract NFT is ERC721Enumerable, Ownable {
  IExit10 public exit10;
  uint256 public immutable transferLockoutPeriodSeconds;

  modifier onlyBondsManager() {
    require(msg.sender == address(exit10), 'BondNFT: Caller must be ChickenBondManager');
    _;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 _transferLockoutPeriodSeconds
  ) ERC721(name_, symbol_) {
    transferLockoutPeriodSeconds = _transferLockoutPeriodSeconds;
  }

  function setChickenBondManager(address _chickenBondManager) external onlyOwner {
    require(_chickenBondManager != address(0), 'BondNFT: _chickenBondManagerAddress must be non-zero');
    require(address(exit10) == address(0), 'BondNFT: setAddresses() can only be called once');

    exit10 = IExit10(_chickenBondManager);
    renounceOwnership();
  }

  function mint(address _bonder) external onlyBondsManager returns (uint256 tokenID) {
    // We actually increase totalSupply in `ERC721Enumerable._beforeTokenTransfer` when we `_mint`.
    tokenID = totalSupply() + 1;

    _mint(_bonder, tokenID);
  }

  function tokenURI(uint256 _tokenID) public view virtual override returns (string memory) {
    require(_exists(_tokenID), 'BondNFT: URI query for nonexistent token');

    return ('uri');
  }

  // Prevent transfers for a period of time after chickening in or out
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenID,
    uint256 _batchSize
  ) internal virtual override {
    if (_from != address(0)) {
      (, , , uint256 endTime, uint8 status) = exit10.getBondData(_tokenID);

      require(
        status == uint8(IExit10.BondStatus.active) || block.timestamp >= endTime + transferLockoutPeriodSeconds,
        'BondNFT: cannot transfer during lockout period'
      );
    }

    super._beforeTokenTransfer(_from, _to, _tokenID, _batchSize);
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
}
