// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Advanced Music NFT Copyright Protection Platform
 * @dev Implements a comprehensive system for music copyright protection using NFTs
 * with advanced features like collaborative ownership, royalty splitting, and fraud prevention
 */
contract AdvancedMusicNFT is 
    ERC721, 
    ERC721URIStorage, 
    ERC721Royalty,
    Pausable, 
    AccessControl,
    ReentrancyGuard 
{
    using Counters for Counters.Counter;
    using ECDSA for bytes32;
    using Strings for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIED_ARTIST_ROLE = keccak256("VERIFIED_ARTIST_ROLE");

    Counters.Counter private _tokenIds;

    // Advanced storage structures
    struct MusicMetadata {
        string title;
        string artist;
        uint256 timestamp;
        string ipfsHash;
        bool isRegistered;
        bytes32 contentHash;    // Hash of the actual music content
        address[] collaborators;
        uint256[] royaltyShares;
        uint256 totalRoyalty;   // Base points (10000 = 100%)
        bool isVerified;        // Verified by platform
        uint256 copyrightExpiryDate;
        mapping(address => bool) hasSignedAgreement;
    }

    struct RoyaltyInfo {
        address[] beneficiaries;
        uint256[] shares;
        uint256 totalCollected;
    }

    // Advanced mappings
    mapping(uint256 => MusicMetadata) private _musicData;
    mapping(uint256 => RoyaltyInfo) private _royalties;
    mapping(bytes32 => bool) private _usedContentHashes;
    mapping(address => uint256[]) private _artistPortfolio;
    mapping(address => uint256) private _artistReputation;
    mapping(uint256 => mapping(address => uint256)) private _pendingRoyalties;

    // Events
    event MusicNFTMinted(
        uint256 indexed tokenId, 
        address indexed artist, 
        string title,
        bytes32 contentHash
    );
    event CopyrightRegistered(
        uint256 indexed tokenId, 
        address indexed artist,
        uint256 expiryDate
    );
    event RoyaltyDistributed(
        uint256 indexed tokenId,
        address[] beneficiaries,
        uint256[] amounts
    );
    event CollaboratorAdded(
        uint256 indexed tokenId,
        address indexed collaborator,
        uint256 share
    );
    event ContentDisputed(
        uint256 indexed tokenId,
        address indexed disputant,
        string reason
    );

    constructor() ERC721("AdvancedMusicNFT", "AMNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Mints a new music NFT with advanced validation and security features
     * @param title Music title
     * @param ipfsHash IPFS hash of the music file
     * @param contentHash Hash of the actual music content
     * @param collaborators Array of collaborator addresses
     * @param royaltyShares Array of royalty shares for each collaborator
     * @param signature Digital signature of content hash
     */
    function mintMusicNFT(
        string memory title,
        string memory ipfsHash,
        bytes32 contentHash,
        address[] memory collaborators,
        uint256[] memory royaltyShares,
        bytes memory signature
    ) public whenNotPaused nonReentrant returns (uint256) {
        require(!_usedContentHashes[contentHash], "Content already registered");
        require(collaborators.length == royaltyShares.length, "Invalid royalty configuration");
        require(_verifyContentSignature(contentHash, signature), "Invalid content signature");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < royaltyShares.length; i++) {
            totalShares += royaltyShares[i];
        }
        require(totalShares == 10000, "Total shares must be 100%");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        // Initialize storage
        MusicMetadata storage metadata = _musicData[newTokenId];
        metadata.title = title;
        metadata.artist = msg.sender;
        metadata.timestamp = block.timestamp;
        metadata.ipfsHash = ipfsHash;
        metadata.contentHash = contentHash;
        metadata.collaborators = collaborators;
        metadata.royaltyShares = royaltyShares;
        metadata.totalRoyalty = 1000; // 10% default royalty

        // Set royalty information
        _setTokenRoyalty(newTokenId, address(this), 1000);

        // Initialize royalty tracking
        RoyaltyInfo storage royaltyInfo = _royalties[newTokenId];
        royaltyInfo.beneficiaries = collaborators;
        royaltyInfo.shares = royaltyShares;

        _safeMint(msg.sender, newTokenId);
        _usedContentHashes[contentHash] = true;
        _artistPortfolio[msg.sender].push(newTokenId);

        emit MusicNFTMinted(newTokenId, msg.sender, title, contentHash);
        return newTokenId;
    }

    /**
     * @dev Registers copyright with advanced validation
     * @param tokenId Token ID
     * @param expiryDate Copyright expiry date
     * @param legalDocHash Hash of legal documentation
     */
    function registerCopyright(
        uint256 tokenId,
        uint256 expiryDate,
        bytes32 legalDocHash
    ) public whenNotPaused nonReentrant {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        require(!_musicData[tokenId].isRegistered, "Already registered");
        require(expiryDate > block.timestamp, "Invalid expiry date");

        MusicMetadata storage metadata = _musicData[tokenId];
        metadata.isRegistered = true;
        metadata.copyrightExpiryDate = expiryDate;

        // Increase artist reputation
        _artistReputation[msg.sender] += 100;

        emit CopyrightRegistered(tokenId, msg.sender, expiryDate);
    }

    /**
     * @dev Distributes pending royalties to collaborators
     * @param tokenId Token ID
     */
    function distributeRoyalties(uint256 tokenId) public nonReentrant {
        RoyaltyInfo storage royaltyInfo = _royalties[tokenId];
        require(royaltyInfo.totalCollected > 0, "No royalties to distribute");

        uint256[] memory amounts = new uint256[](royaltyInfo.beneficiaries.length);
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < royaltyInfo.beneficiaries.length; i++) {
            address beneficiary = royaltyInfo.beneficiaries[i];
            uint256 share = royaltyInfo.shares[i];
            
            uint256 amount = (royaltyInfo.totalCollected * share) / 10000;
            amounts[i] = amount;
            totalDistributed += amount;
            
            _pendingRoyalties[tokenId][beneficiary] += amount;
        }

        royaltyInfo.totalCollected = 0;

        emit RoyaltyDistributed(tokenId, royaltyInfo.beneficiaries, amounts);
    }

    /**
     * @dev Verifies content signature to prevent fraud
     * @param contentHash Hash of the content
     * @param signature Digital signature
     */
    function _verifyContentSignature(
        bytes32 contentHash,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            contentHash
        ));
        address signer = messageHash.recover(signature);
        return hasRole(VERIFIED_ARTIST_ROLE, signer);
    }

    /**
     * @dev Gets comprehensive metadata for a token
     * @param tokenId Token ID
     */
    function getMusicMetadata(uint256 tokenId) public view returns (
        string memory title,
        address artist,
        uint256 timestamp,
        string memory ipfsHash,
        bool isRegistered,
        address[] memory collaborators,
        uint256[] memory royaltyShares,
        bool isVerified,
        uint256 copyrightExpiryDate
    ) {
        MusicMetadata storage metadata = _musicData[tokenId];
        return (
            metadata.title,
            metadata.artist,
            metadata.timestamp,
            metadata.ipfsHash,
            metadata.isRegistered,
            metadata.collaborators,
            metadata.royaltyShares,
            metadata.isVerified,
            metadata.copyrightExpiryDate
        );
    }

    // Override required functions
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage, ERC721Royalty) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Royalty, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
