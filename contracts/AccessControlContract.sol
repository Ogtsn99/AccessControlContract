//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "hardhat/console.sol";

contract AccessControlContract is ERC721, Ownable {
    using Strings for uint256;

    string public baseURIextended;
    uint256 public nextTokenId;

    // mapping from content Id to author address
    mapping(string => address) private _authors;
    // mapping from content Name to token Id.
    //mapping(uint256 => uint256[]) private _tokens;
    // mapping from token Id to content Name
    mapping(uint256 => string) private _contents;
    // mapping from contentName to content SHA256 merkleRoot
    // どうしてハッシュをipfsに記録しないか -> ぶっちゃけIPFSに保存しても良い
    // スピードの問題。ガス代はかかるが、ハッシュを取ってくるのに時間をあまりかけたくないと思ったため。
    mapping(string => string) private _contentMerkleRoots;
    // mapping from content Name to ipfsPath
    mapping(string => string) private _ipfsPaths;
    // mapping from content Name to price you need to pay when minting
    mapping(string => uint256) private _prices;
    // mapping from tokenId to address by whom actually have content's ownership
    mapping(uint256 => address) private _ownershipGrantedAddresses;
    // mapping from content Name to mapping from address to the number of ownerships.
    mapping(string => mapping(address => uint256)) private ownerships;

    constructor(string memory name_, string memory symbol_)
    ERC721(name_, symbol_)
    {}

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721)
    returns (bool)
    {
        return ERC721.supportsInterface(interfaceId);
    }

    event Register(address indexed author, string indexed contentName);
    event SetPrice(string indexed contentName, uint256 price);
    event SetRoyalty(string indexed contentName, uint256 royalty, address receiver);
    event SetContentMerkleRoot(string indexed contentName, string merkleRoot);
    event SetIpfsPath(string indexed contentName, string path);

    function register(uint256 price, string memory contentName, string memory merkleRoot) public {
        register(price, contentName, merkleRoot, "");
    }

    function register(uint256 price, string memory contentName, string memory merkleRoot, string memory path) public {
        require(_authors[contentName] != address(0), "The content has already registered");
        _authors[contentName] = msg.sender;

        if(price != 0) {
            _prices[contentName] = price;
            emit SetPrice(contentName, price);
        }

        if(bytes(merkleRoot).length != 0) {
            _contentMerkleRoots[contentName] = merkleRoot;
            emit SetContentMerkleRoot(contentName, merkleRoot);
        }

        if(bytes(path).length != 0) {
            _ipfsPaths[contentName] = path;
            emit SetIpfsPath(contentName, path);
        }

        emit Register(msg.sender, contentName);
    }

    function setPrice(string memory conetntName, uint256 price) public {
        require(msg.sender == _authors[conetntName], "you are not the author");
        _prices[conetntName] = price;
        emit SetPrice(conetntName, price);
    }

    function setContentMerkleRoot(string memory contentName, string memory merkleRoot) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _contentMerkleRoots[contentName] = merkleRoot;
        emit SetContentMerkleRoot(contentName, merkleRoot);
    }

    function setIpfsPath(string memory contentName, string memory path) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _ipfsPaths[contentName] = path;
        emit SetIpfsPath(contentName, path);
    }

    /// @notice Mint one token to `to`
    /// @param contentName an id of the content
    /// @param to the recipient of the token
    function mint(
        string memory contentName,
        address to
    ) payable external {

        bool isAuthor = _authors[contentName] == msg.sender;
        require(_prices[contentName] == msg.value || isAuthor,
            "you are not the author and msg.value is not equal to the price");

        if(!isAuthor) {
            payable(_authors[contentName]).transfer(msg.value);
        }

        uint256 tokenId = nextTokenId;

        _contents[tokenId] = contentName;

        _safeMint(to, tokenId, '');

        nextTokenId = tokenId + 1;
    }

    function setBaseURI(string memory baseURI_) public onlyOwner() {
        baseURIextended = baseURI_;
    }

    function hasOwnership(address account, string memory contentName) public view returns(bool) {
        return ownerships[contentName][account] != 0 || _authors[contentName] == account;
    }

    function contentNameOf(uint256 tokenId) public view returns (string memory) {
        require(ownerOf(tokenId) != address(0), "token not existed");
        return _contents[tokenId];
    }

    function authorOf(string memory contentName) public view returns (address) {
        return _authors[contentName];
    }

    function priceOf(string memory contentName) public view returns (uint256) {
        return _prices[contentName];
    }

    function merkleRootOf(string memory contentName) public view returns (string memory) {
        return _contentMerkleRoots[contentName];
    }

    function ipfsPathOf(string memory contentName) public view returns (string memory) {
        return _ipfsPaths[contentName];
    }

    function contentURI(string memory contentName) public view returns (string memory) {
        string memory baseURI = _baseURI();
        return bytes(_ipfsPaths[contentName]).length > 0 ? string(abi.encodePacked(baseURI, _ipfsPaths[contentName])) : "";
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _ipfsPaths[_contents[tokenId]])) : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURIextended;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if(from != address(0)) {
            ownerships[_contents[tokenId]][_ownershipGrantedAddresses[tokenId]] -= 1;
        }
        if(to != address(0)) {
            _ownershipGrantedAddresses[tokenId] = to;
            ownerships[_contents[tokenId]][to] += 1;
        }
    }
}