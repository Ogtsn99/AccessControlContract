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
    // mapping from tokenId to address by whom actually have content's accessRight
    mapping(uint256 => address) private _accessRightGrantedAddresses;
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

    function register(uint256 price, string memory contentName, string memory merkleRoot) public {
        require(bytes(_contentMerkleRoots[contentName]).length == 0);
        _authors[contentName] = msg.sender;
        _prices[contentName] = price;
        _contentMerkleRoots[contentName] = merkleRoot;
        _content_title_list.push(contentName);
    }

    function setPrice(string memory contentName, uint256 price) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _prices[contentName] = price;
    }

    function setContentMerkleRoot(string memory contentName, string memory merkleRoot) public {
        require(msg.sender == _authors[contentName], "you are not the author");
        _contentMerkleRoots[contentName] = merkleRoot;
    }

    /// @notice Mint one token to `to`
    /// @param contentName an id of the content
    /// @param to the recipient of the token
    function mint(
        string memory contentName,
        address to
    ) payable external {
        require(_prices[contentName] == msg.value);
        payable(_authors[contentName]).transfer(msg.value);
        _contents[nextTokenId] = contentName;
        _safeMint(to, nextTokenId, '');
        nextTokenId++;
    }

    function hasAccessRight(address account, string memory contentName) public view returns(bool) {
        return _accessRights[contentName][account] != 0 || _authors[contentName] == account;
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
        require(msg.value == registration_fee, "Registration fee is required.");
        uint group = next_group();
        group = next_group();
        _groupNodeCounter[group] += 1;
        _groups[peer_id] = group;
        require(_peer_id_account_map[peer_id] == address(0));
        _peer_id_account_map[peer_id] = msg.sender;
        _account_peer_id_map[msg.sender] = peer_id;
    }

    // テスト用
    function forceDispatchNodeForTesting(string memory peer_id, uint group) public {
        require(_groups[peer_id] == 0, "This peer is already used.");
        _groupNodeCounter[group] += 1;
        _groups[peer_id] = group;
        require(_peer_id_account_map[peer_id] == address(0));
        _peer_id_account_map[peer_id] = msg.sender;
        _account_peer_id_map[msg.sender] = peer_id;
    }

    function leaveNode() public {
        string memory peer_id = _account_peer_id_map[msg.sender];
        uint group = _groups[peer_id];
        require(group != 0, "This peer_id is not registered.");
        _groups[peer_id] = 0;
        _groupNodeCounter[group] -= 1;
        _peer_id_account_map[peer_id] = address(0);
        _account_peer_id_map[msg.sender] = "";
        payable(msg.sender).transfer(registration_fee);
    }

    function next_group() public view returns (uint) {
        uint group = 0;
        uint mi = 1000000007;
        for (uint i=1; i<=40; i++) {
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if(from != address(0)) {
            _accessRights[_contents[tokenId]][_accessRightGrantedAddresses[tokenId]] -= 1;
        }
        if(to != address(0)) {
            _accessRightGrantedAddresses[tokenId] = to;
            _accessRights[_contents[tokenId]][to] += 1;
        }
    }

    // 以下、インセンティブシステム用
    mapping(uint=>mapping(uint=>mapping(bytes32=>bool))) private _is_encrypted_answer_exist;
    mapping(uint=>mapping(uint=>mapping(address=>uint))) private _deposits;
    mapping(uint=>mapping(uint=>mapping(address=>bytes32))) private _answers;
    mapping(uint=>mapping(uint=>mapping(bytes32=>uint))) private _answer_counts;
    mapping(uint=>mapping(uint=>bytes32[])) private _answers_lists;
    // block.numberを変える方法がわからないので仮想block.numberを使う
    uint public v_block_num = 0;

    function set_virtual_block_num(uint block_num) public {
        v_block_num = block_num;
    }

    function vote(bytes32 encrypted_answer) payable public {
        require(v_block_num % 300 < 100, "Out of voting period.");
        uint id = v_block_num / 300;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        require(group > 0, "This node is not registered.");
        require(_is_encrypted_answer_exist[id][group][encrypted_answer] == false);
        _is_encrypted_answer_exist[id][group][encrypted_answer] = true;
        require(msg.value != 0 && _deposits[id][group][msg.sender] == 0);
        _deposits[id][group][msg.sender] = msg.value;
    }

    function disclosure(bytes32 answer, bytes32 key) public {
        uint id = v_block_num / 300;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        require((v_block_num % 300) >= 100 && (v_block_num % 300) < 200, "Out of disclosure period.");
        require(_is_encrypted_answer_exist[id][group][keccak256(abi.encode(answer, key))], "invalid answer and key");
        _answers[id][group][msg.sender] = answer;
        _answer_counts[id][group][answer] += 1;
        if (_answer_counts[id][group][answer] == 1) {
            _answers_lists[id][group].push(answer);
        }
    }

    function claim() public {
        uint id = v_block_num / 300;
        uint group = _groups[_account_peer_id_map[msg.sender]];
        require((v_block_num % 300) >= 200 && (v_block_num % 300) < 300, "Out of disclosure period.");
        uint ma = 0;
        for (uint i=0; i<_answers_lists[id][group].length; i++) {
            if (ma < _answer_counts[id][group][_answers_lists[id][group][i]]) {
                ma = _answer_counts[id][group][_answers_lists[id][group][i]];
            }
        }
        bytes32 correct = 0;
        for (uint i=0; i<_answers_lists[id][group].length; i++) {
            if (ma == _answer_counts[id][group][_answers_lists[id][group][i]]) {
                require(correct == 0, "No correct answer");
                correct = _answers_lists[id][group][i];
            }
        }
        require(correct == _answers[id][group][msg.sender], "Your answer is wrong");
        dbt.mint(msg.sender, _deposits[id][group][msg.sender] * 1000);
        _deposits[id][group][msg.sender] = 0;
    }

    // 動作確認用
    function is_encrypted_answer_exist(uint block_num, bytes32 encrypted_answer, uint group) public view returns (bool) {
        return _is_encrypted_answer_exist[block_num / 300][group][encrypted_answer];
    }
    function get_answer_counts(uint block_num, uint group, bytes32 answer) public view returns (uint) {
        return _answer_counts[block_num / 300][group][answer];
    }
}