const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Quyx", () => {
  async function deployContract() {
    [owner, user1, user2] = await ethers.getSigners();

    const Contract = await ethers.getContractFactory("Quyx");
    const baseURL = "https://api.quyx.xyx/card/";
    const contract = await Contract.connect(owner).deploy(baseURL);
    await contract.waitForDeployment();
    const contractAddress = contract.target;

    return { contract, baseURL, contractAddress, owner, user1, user2 };
  }

  describe("Deployment", () => {
    it("Should set the right owner of the contract", async () => {
      const { contract, owner } = await loadFixture(deployContract);

      expect(await contract.owner()).to.eq(owner);
    });

    it("Should set the right baseURL", async () => {
      const { contract, baseURL } = await loadFixture(deployContract);

      expect(await contract.baseURL).to.eq(baseURL);
    });
  });

  describe("onlyOwner utils fn(s)", () => {});
});
