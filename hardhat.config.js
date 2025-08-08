require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");      // ethers + chai matchers + verify + helpers
require("@openzeppelin/hardhat-upgrades");        // UUPS/proxy tools
require("@nomiclabs/hardhat-web3");               // kalau perlu web3.js
// (Jangan pakai @nomiclabs/hardhat-waffle agar tidak konflik)

task("accounts", "Prints the list of accounts", async (_, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const a of accounts) console.log(a.address);
});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          optimizer: { enabled: true, runs: 1 },
        },
      },
      {
        version: "0.8.9",
        settings: {
          optimizer: { enabled: true, runs: 1 },
        },
      },
    ],
  },

  sourcify: { enabled: false },

  gasReporter: {
    enabled: true,
    currency: "EUR",
    L1: "ethereum",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY || "",
  },

  networks: {
    hardhat: {
      // forking contoh (opsional):
      // forking: {
      //   url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
      // },
    },
    testnet: {
      url: "https://1rpc.io/sepolia",
      accounts: [process.env.PRIVATE_KEY].filter(Boolean),
    },
    base: {
      url: "https://base.llamarpc.com",
      accounts: [process.env.PRIVATE_KEY].filter(Boolean),
    },
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};

