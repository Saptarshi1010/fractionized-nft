// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// NFT Factory
contract Digitalizer is ERC721, ERC721Enumerable, Ownable, IERC721Receiver {
    error InitializingAuctionFailed();

    /// @dev Variables
    address private immutable auctioner;

    /// @dev Arrays
    uint[] private s_receivedTokens;

    event AuctionInitializedSuccessfully();

    constructor(address _auctioner, string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {
        auctioner = _auctioner;
    }

    function safeMint() external onlyOwner {
        _safeMint(address(this), totalSupply());
    }

    function initialize(uint _tokenId, uint _nftFractionsAmount, uint _price) external onlyOwner {
        IERC721(address(this)).approve(auctioner, _tokenId);

        (bool success, ) = auctioner.call(
            abi.encodeWithSignature("schedule(address,uint256,uint256,uint256)", address(this), _tokenId, _nftFractionsAmount, _price)
        );
        if (!success) revert InitializingAuctionFailed();

        emit AuctionInitializedSuccessfully();
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function onERC721Received(address /* operator */, address /* from */, uint _tokenId, bytes memory /* data */) public override returns (bytes4) {
        s_receivedTokens.push(_tokenId);

        return this.onERC721Received.selector;
    }
}
