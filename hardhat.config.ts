import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || ""; 


const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200, // Adjust the runs value as needed
      },
    },
  },
  networks: {
    assetChainTestnet: {
      url: "https://enugu-rpc.assetchain.org/",
      chainId: 42421,
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      // Replace with the actual API key for Asset Chain Testnet if available
      assetChainTestnet: ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: "assetChainTestnet",
        chainId: 42421,
        urls: {
          apiURL: "https://scan-testnet.assetchain.org/api",
          browserURL: "https://scan-testnet.assetchain.org/",
        },
      },
    ],
  },
};

export default config;
