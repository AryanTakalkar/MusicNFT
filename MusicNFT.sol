// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MusicNFT is ERC721URIStorage, Ownable {
    uint256 private _tokenIdCounter;
    mapping(uint256 => address) public originalCreators;
    mapping(uint256 => uint256) public royalties; // in basis points (100 = 1%)
    
    event MusicNFTMinted(uint256 tokenId, address artist, string metadataURI);
    event RoyaltyPaid(uint256 tokenId, address recipient, uint256 amount);

    constructor() ERC721("MusicNFT", "MNFT") {}
    
    function mintMusicNFT(string memory metadataURI, uint256 royalty) external {
        require(royalty <= 1000, "Royalty cannot exceed 10%");
        uint256 tokenId = _tokenIdCounter++;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);
        originalCreators[tokenId] = msg.sender;
        royalties[tokenId] = royalty;

        emit MusicNFTMinted(tokenId, msg.sender, metadataURI);
    }

    function transferWithRoyalty(address from, address to, uint256 tokenId) external payable {
        require(ownerOf(tokenId) == from, "Sender must own the token");
        uint256 royaltyFee = (msg.value * royalties[tokenId]) / 10000;

        if (royaltyFee > 0) {
            payable(originalCreators[tokenId]).transfer(royaltyFee);
            emit RoyaltyPaid(tokenId, originalCreators[tokenId], royaltyFee);
        }
        _transfer(from, to, tokenId);
    }
}
