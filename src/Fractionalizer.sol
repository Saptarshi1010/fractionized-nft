// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Owner of this contract will be Auctioner -> this is template for our ERC20 tokens with voting privileges
contract Fractionalizer is ERC20, Ownable, ERC20Permit, ERC20Votes {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) ERC20Permit(name) {}

    function mint(address to, uint amount) external onlyOwner {
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function delegateVotes(address delegatee) external {
        _delegate(delegatee, delegatee);
    }

    function _update(address from, address to, uint value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint) {
        return super.nonces(owner);
    }
}
