import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config(); // Load environment variables from .env file

async function main() {

    const PRIVATE_KEY = process.env.PRIVATE_KEY; // Access the private key from .env
    const INITIAL_REWARD_DROP = 27500;

    if (!PRIVATE_KEY) {
        throw new Error("PRIVATE_KEY is not defined in the environment variables.");
    }
    // Create a wallet instance from the private key
    const wallet = new ethers.Wallet(PRIVATE_KEY);
    
    const ownerAddress = wallet.address; // Get the owner's address from the wallet

    console.log("Owner Address:", ownerAddress);

    
    const stakeContractFactory = await ethers.getContractFactory("RWANativeStake");

    const rewardDrop = ethers.parseEther(INITIAL_REWARD_DROP.toString());  // Convert 27500 to wei


    const stakeContract = await upgrades.deployProxy(stakeContractFactory, [rewardDrop,ownerAddress,], {initializer: "initialize"});

    

    console.log("RWANativeStake proxy deployed to:", stakeContract.target);
    

    // Retrieve the implementation contract address
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(stakeContract.target.toString());

    console.log("RWANativeStake implementation deployed to:", implementationAddress); // Log the implementation address


}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });