import { assert, expect } from "chai";
import { ethers } from "hardhat";
import { AccessControlContract } from "../typechain";
import { Signer } from "ethers";

describe("ARC", function () {
  let AccessControlContract;
  let art: AccessControlContract;
  let author: Signer, buyer: Signer, provider: Signer, provider2: Signer;
  
  before(async ()=> {
    AccessControlContract = await ethers.getContractFactory("AccessControlContract");
    art = await AccessControlContract.deploy("AccessControlToken", "ART");
    await art.deployed();
    [author, buyer, provider, provider2] = await ethers.getSigners();
  })
  
  it("Should return the name", async function () {
    expect(await art.name()).to.equal("AccessControlToken");
  });
  
  it("Should success register", async function () {
    await art.connect(author).register(1, "test", "test");
    let title = await art.functions.authorOf("test");
    assert.isTrue((await art.functions.hasAccessRight(await author.getAddress(), "test"))[0]);
  })

  it('can register node', async function () {
    let next = await art.connect(provider).functions.next_group();
    await art.connect(provider).functions.registerNode("peer_id");
    let group = await art.functions.get_group("peer_id");
    assert.equal(group.toString(), "1");
  
    await art.connect(provider2).functions.registerNode( "peer_id2");
    group = await art.functions.get_group("peer_id2");
    assert.equal(group.toString(), "2");
  });
});
