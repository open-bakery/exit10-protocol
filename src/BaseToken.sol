// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol';

contract BaseToken is ERC20Permit, Ownable {
  constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

  function mint(address _to, uint256 _amount) external virtual onlyOwner {
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external virtual onlyOwner {
    _burn(_from, _amount);
  }
}
