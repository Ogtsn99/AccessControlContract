// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
let data = require("../ids.json");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  
  const AccessControlContract = await ethers.getContractFactory("AccessControlContract");
  const acc = await AccessControlContract.deploy("AccessRightToken", "ART");
  
  await acc.deployed();
  console.log(acc.address);
  
  let [signers1, signers2] = await ethers.getSigners();
  console.log(signers1.address, signers2.address)
  console.log("Access Control Contract deployed to:", acc.address);
  await acc.connect(signers1).functions.register(1, "sample.txt", "76ea42bc8abb0fc5bfc74ac7a777d35d7a3f0bf1db514c498f3a463b91a59310");
  await acc.connect(signers1).functions.register(1, "1MB_Sample", "b90d019c4553c7a4ca5ce226a00c38fb99d2db7d9c9d29b68386d9d3fef8b645");
  await acc.connect(signers1).functions.register(1, "10MB_Sample", "4be1492cb7259e7d9faebdb443583cd962010f4aeaffaea535136a2551955111");
  await acc.connect(signers1).functions.register(1, "100MB_Sample", "88cea1759ac6e2f6bb94cd74cb6cbdf6d928aac6d2d2424da17d51e156d33a79");
  // await acc.connect(signers1).functions.node_register(1, "12D3KooWPjceQrSwdWXPyLLeABRXmuqt69Rg3sBYbU1Nft9HyQ6X");
  // let group = await acc.connect(signers1).functions.get_group("12D3KooWPjceQrSwdWXPyLLeABRXmuqt69Rg3sBYbU1Nft9HyQ6X");
  // console.log("GROUP:", group);
  
  data = data.sort(function(a: any, b: any) {
    if (a.group < b.group) return -1;
    else return 1;
  })
  
  for (let i = 0; i < data.length; i++) {
    let private_key = data[i]['private_key'];
    const signer = new ethers.Wallet(private_key, signers1.provider);
    await signers1.sendTransaction({to: await signer.getAddress(), value: "70659367520504688"});
    await acc.connect(signer).functions.registerNode(data[i].peer_id);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
