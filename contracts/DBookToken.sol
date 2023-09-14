//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract DBookToken is ERC20 {
    bool enableFaucet;
    address accAddress;

    constructor(
        string memory name,
        string memory symbol,
        address _accAddress
    ) ERC20(name, symbol) {
        accAddress = _accAddress;
    }

    function mint(address to, uint amount) public {
        require(accAddress == msg.sender);
        _mint(to, amount);
    }
}