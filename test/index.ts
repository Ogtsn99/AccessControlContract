import { assert, expect } from "chai";
import { ethers } from "hardhat";
import { AccessControlContract } from "../typechain";
import { Signer } from "ethers";

describe("ARC", function () {
  let AccessControlContract;
  let art: AccessControlContract;
  let author: Signer, buyer: Signer;
  
  before(async ()=> {
    AccessControlContract = await ethers.getContractFactory("AccessControlContract");
    art = await AccessControlContract.deploy("AccessControlToken", "ART");
    await art.deployed();
    [author, buyer] = await ethers.getSigners();
  })
  
  it("Should return the name", async function () {
    expect(await art.name()).to.equal("AccessControlToken");
  });
  
  it("Should success register", async function () {
    await art.connect(author).register(1, "test", "test");
    let title = await art.functions.authorOf("test");
    assert.isTrue((await art.functions.hasAccessRight(await author.getAddress(), "test"))[0]);
  })
});
