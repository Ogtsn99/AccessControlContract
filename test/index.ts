import { assert, expect } from "chai";
import { ethers } from "hardhat";
import { AccessControlContract, DBookToken } from "../typechain";
import { ContractTransaction, Signer, utils } from "ethers";
import { keccak256 } from "ethers/lib/utils";

async function assertPromiseThrow(p: Promise<any>) {
  let error: any;
  return p.catch((err) => {
    error = err;
  }).finally(()=> {
    expect(error).to.be.an(`Error`);
  })
}

describe("ARC", function () {
  let AccessControlContract;
  let DBookTokenContract;
  let art: AccessControlContract;
  let dbt: DBookToken;
  let author: Signer, buyer: Signer, provider: Signer, provider2: Signer;
  
  before(async ()=> {
    DBookTokenContract = await ethers.getContractFactory("DBookToken");
    AccessControlContract = await ethers.getContractFactory("AccessControlContract");
    art = await AccessControlContract.deploy("AccessControlToken", "ART");
    await art.deployed();
    dbt = await DBookTokenContract.deploy("DBookToken", "DBT", art.address);
    await dbt.deployed();
    await art.setDBookToken(dbt.address);
    [author, buyer, provider, provider2] = await ethers.getSigners();
  })
  
  it("can mint dbt", async function () {
    await art.connect(author).mintDBT();
    assert.equal((await dbt.balanceOf(await author.getAddress())).toString(), "114514");
  })
  
  it("Should return the name", async function () {
    expect(await art.name()).to.equal("AccessControlToken");
  });
  
  it("Should success register", async function () {
    await art.connect(author).register(1, "test", "test");
    let title = await art.functions.authorOf("test");
    assert.isTrue((await art.functions.hasAccessRight(await author.getAddress(), "test"))[0]);
  })
  
  it("can buy e-book NFT", async function () {
    await art.connect(buyer).mint("test", await buyer.getAddress(), {value: "1"});
    assert.isTrue((await art.functions.hasAccessRight(await buyer.getAddress(), "test"))[0]);
  })

  it('can register node', async function () {
    let next = await art.connect(provider).functions.next_group();
    await art.connect(provider).functions.registerNode("peer_id", {value: "10000"});
    let group = await art.functions.get_group("peer_id");
    assert.equal(group.toString(), "1");
  
    await art.connect(provider2).functions.registerNode( "peer_id2", {value: "10000"});
    group = await art.functions.get_group("peer_id2");
    assert.equal(group.toString(), "2");
  });

  // グループのノードが一人だけ
  it('can vote', async function () {
    await art.connect(provider).set_virtual_block_num(1);
    await art.connect(provider).vote(keccak256(utils.toUtf8Bytes("testtesttesttesttesttesttesttestkeykeykeykeykeykeykeykeykeykeyke")), {value: "10000"});
    await art.connect(provider).set_virtual_block_num(101);
    await art.connect(provider).disclosure(
      utils.toUtf8Bytes("testtesttesttesttesttesttesttest"),
      utils.toUtf8Bytes("keykeykeykeykeykeykeykeykeykeyke"));
    await art.set_virtual_block_num(202);
    await art.connect(provider).claim();
    console.log(await dbt.balanceOf(await provider.getAddress()));
    assert.equal((await dbt.balanceOf(await provider.getAddress())).toString(), "10000000");
  });

  // グループのノードが一人だけ
  it('can vote 3 people', async function () {
    let {4: a, 5: b, 6:c} = await ethers.getSigners()
    // 投票期間
    await art.set_virtual_block_num(303);
    let correctAnswer = "testtesttesttesttesttesttesttest";
    let wrongAnswer = "wrongwrongwrongwrongwrongwrongwr";
    let a_key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let b_key = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let c_key = "cccccccccccccccccccccccccccccccc";

    await art.connect(a).forceDispatchNodeForTesting(await a.getAddress(), 10);
    await art.connect(b).forceDispatchNodeForTesting(await b.getAddress(), 10);
    await art.connect(c).forceDispatchNodeForTesting(await c.getAddress(), 10);

    await art.connect(a).vote(keccak256(utils.toUtf8Bytes(correctAnswer + a_key)), {value: "10000"});
    await art.connect(b).vote(keccak256(utils.toUtf8Bytes(correctAnswer + b_key)), {value: "20000"});
    await art.connect(c).vote(keccak256(utils.toUtf8Bytes(wrongAnswer + c_key)), {value: "1"});

    // 開票期間
    await art.set_virtual_block_num(404);
    await art.connect(a).disclosure(utils.toUtf8Bytes(correctAnswer), utils.toUtf8Bytes(a_key));
    await art.connect(b).disclosure(utils.toUtf8Bytes(correctAnswer), utils.toUtf8Bytes(b_key));
    await art.connect(c).disclosure(utils.toUtf8Bytes(wrongAnswer), utils.toUtf8Bytes(c_key));

    // 請求期間
    await art.set_virtual_block_num(505);
    await art.connect(a).claim();
    await art.connect(b).claim();
    await assertPromiseThrow(art.connect(c).claim());
    assert.equal((await dbt.balanceOf(await a.getAddress())).toString(), '10000000');
    assert.equal((await dbt.balanceOf(await b.getAddress())).toString(), '20000000');
    assert.equal((await dbt.balanceOf(await c.getAddress())).toString(), '0');
    
    await art.connect(a).leaveNode();
  });
});
