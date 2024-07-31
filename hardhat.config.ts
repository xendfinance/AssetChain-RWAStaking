import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";

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
};

export default config;
