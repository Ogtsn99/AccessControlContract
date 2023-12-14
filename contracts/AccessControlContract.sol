//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "hardhat/console.sol";
import "./DBookToken.sol";

contract AccessControlContract is ERC721, Ownable {
    using Strings for uint256;

    // contentName is used as ids. All of them should be unique
    uint256 public nextTokenId;
    // mapping from contentName to author address
    mapping(string => address) private _authors;
    // mapping from token Id to content Name
    mapping(uint256 => string) private _contents;
    // mapping from contentName to content SHA256 merkleRoot
    // どうしてハッシュをipfsに記録しないか -> ぶっちゃけIPFSに保存しても良い
    // スピードの問題。ガス代はかかるが、ハッシュを取ってくるのに時間をあまりかけたくないと思ったため。
    mapping(string => string) private _contentMerkleRoots;
    // mapping from content Name to price you need to pay when minting
    mapping(string => uint256) private _prices;
    // mapping from content Name to mapping from address to the number of _accessRights.
    mapping(string => mapping(address => uint256)) private _accessRights;
    // mapping from groupId to number of active nodes 1 indexed
    mapping(uint256 => uint256) private _groupNodeCounter;
    // mapping from address to group assigned 1 indexed
    mapping(string => uint256) private _groups;
    mapping(address => string) private _account_peer_id_map;
    mapping(string => address) private _peer_id_account_map;
    string[] private _content_title_list;
    uint256 public registration_fee = 10000;
    uint public event_length = 300;
    uint public node_number = 40;
    DBookToken dbt;

    constructor(string memory name_, string memory symbol_)
    ERC721(name_, symbol_)
    {}

    function setDBookToken(address _dbt) public {
        require(msg.sender == Ownable.owner());
        dbt = DBookToken(_dbt);
    }

    // テスト用
    function mintDBT() public {
        dbt.mint(msg.sender, 114514);
    }

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721)
    returns (bool)
    {
        return ERC721.supportsInterface(interfaceId);
    }

    function register(uint256 price, string memory title, string memory merkleRoot) public {
        require(bytes(_contentMerkleRoots[title]).length == 0);
        _authors[title] = msg.sender;
        _prices[title] = price;
        _contentMerkleRoots[title] = merkleRoot;
        _content_title_list.push(title);
    }

    function setPrice(string memory contentName, uint256 price) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _prices[contentName] = price;
    }

    function setContentMerkleRoot(string memory contentName, string memory merkleRoot) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _contentMerkleRoots[contentName] = merkleRoot;
    }

    function mint(string memory title, address to) payable external {
        require(_prices[title] == msg.value);
        payable(_authors[title]).transfer(msg.value);
        _contents[nextTokenId] = title;
        _safeMint(to, nextTokenId, '');
        nextTokenId++;
    }

    function hasAccessRight(address account, string memory title) public view returns(bool) {
        return _accessRights[title][account] != 0 || _authors[title] == account;
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

    // TODO: 未定だけど登録に仮想通貨の支払いを必要にする可能性？
    // 同じpeer_idが存在しないようにしたい
    function registerNode(string memory peer_id) payable public {
        require(_groups[peer_id] == 0, "This peer is already used.");
        // require(msg.value == registration_fee, "Registration fee is required.");
        uint group = next_group();
        _groupNodeCounter[group]++;
        _groups[peer_id] = group;
        _account_peer_id_map[msg.sender] = peer_id;
    }

    // テスト用
    function forceDispatchNodeForTesting(string memory peer_id, uint group) public {
        require(_groups[peer_id] == 0, "This peer is already used.");
        _groupNodeCounter[group] += 1;
        _groups[peer_id] = group;
        _account_peer_id_map[msg.sender] = peer_id;
    }

    function leaveNode() public {
        string memory peer_id = _account_peer_id_map[msg.sender];
        uint group = _groups[peer_id];
        require(group != 0, "This peer is not registered.");
        _groups[peer_id] = 0;
        _groupNodeCounter[group]--;
        _account_peer_id_map[msg.sender] = "";
        payable(msg.sender).transfer(registration_fee);
    }

    function next_group() public view returns (uint) {
        uint group = 1;
        uint mi = _groupNodeCounter[1];
        for (uint i=2; i<=node_number; i++) {
            if (mi > _groupNodeCounter[i]) {
                mi = _groupNodeCounter[i];
                group = i;
            }
        }
        return group;
    }

    // 1-indexedで帰ってくる。登録されていない場合は0が帰る
    function get_group(string memory peer_id) public view returns (uint) {
        return _groups[peer_id];
    }

// This function is called when minting.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    ) internal override {
        if(from != address(0)) _accessRights[_contents[tokenId]][from]--;
        _accessRights[_contents[tokenId]][to]++;
    }

    // 以下、インセンティブシステム用
    mapping(uint=>mapping(uint=>mapping(bytes32=>bool))) private encrypted_answer_exists;
    mapping(uint=>mapping(uint=>mapping(address=>uint))) private _deposits;
    mapping(uint=>mapping(uint=>mapping(address=>bytes32))) private _answers;
    mapping(uint=>mapping(uint=>mapping(bytes32=>uint))) private _answer_counts;
    mapping(uint=>mapping(uint=>bytes32[])) private _answer_lists;
    // block.numberを変える方法がわからないので仮想block.numberを使う
    uint public v_block_num = 0;

    function set_virtual_block_num(uint block_num) public {
        v_block_num = block_num;
    }

    function vote(bytes32 encrypted_answer) payable public {
        require(v_block_num % event_length < event_length/3, "Out of voting period.");
        uint event_id = v_block_num / event_length;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        require(!encrypted_answer_exists[event_id][group][encrypted_answer], "The same answer already submitted.");
        require(group > 0, "You aren't registered.");
        encrypted_answer_exists[event_id][group][encrypted_answer] = true;
        _deposits[event_id][group][msg.sender] += msg.value;
    }

    function disclosure(bytes32 answer, bytes32 key) public {
        require(v_block_num % event_length >= event_length/3 && v_block_num % event_length < event_length*2/3, "Out of disclosure period.");
        uint event_id = v_block_num / event_length;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        require(encrypted_answer_exists[event_id][group][keccak256(abi.encode(answer, key))], "invalid answer and key");
        require(_answers[event_id][group][msg.sender] == bytes32(0), "Answer already disclosed.");
        _answers[event_id][group][msg.sender] = answer;
        if (++_answer_counts[event_id][group][answer] == 1) _answer_lists[event_id][group].push(answer);
    }

    function claim() public {
        require((v_block_num % event_length) >= event_length*2/3, "Out of disclosure period.");
        uint event_id = v_block_num / event_length;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        bytes32 ans = _answers[event_id][group][msg.sender];
        uint ans_cnt = _answer_counts[event_id][group][ans];
        for (uint i=0; i < _answer_lists[event_id][group].length; i++) {
            bytes32 ans_i = _answer_lists[event_id][group][i];
            require(ans_i == ans || _answer_counts[event_id][group][ans_i] < ans_cnt, "Your answer is wrong");
        }
        uint deposit = _deposits[event_id][group][msg.sender];
        _deposits[event_id][group][msg.sender] = 0;
        payable(msg.sender).transfer(deposit);
        dbt.mint(msg.sender, deposit * 1000); // reward
    }
}