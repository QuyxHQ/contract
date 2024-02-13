require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "localhost",
  networks: {
    localhost: { url: "http://127.0.0.1:8545" },
    testnet: {
      url: "#",
      accounts: [process.env.PRIVATE_KEY],
    },
    mainnet: {
      url: "#",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  solidity: { compilers: [{ version: "0.8.0" }, { version: "0.8.2" }] },
  mocha: { timeout: 40000 },
};
