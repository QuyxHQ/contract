const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const Contract = await hre.ethers.getContractFactory("Quyx");

  const baseURL = "https://api.quyx.xyz/card/";
  const contract = await Contract.deploy(baseURL);
  await contract.waitForDeployment();

  const address = JSON.stringify({ address: contract.target }, null, 4);

  fs.writeFile("./data/contractAddress.json", address, "utf-8", (err) => {
    if (err) {
      console.error(err);
      return;
    }

    console.log("Contract address:", contract.target);
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
