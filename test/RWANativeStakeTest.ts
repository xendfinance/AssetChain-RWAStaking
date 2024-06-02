import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";

  
describe("RWA Native Stake Contract", function(){


    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.

    async function deployContractFixture(){

      
      const [owner, addr1, addr2] = await hre.ethers.getSigners();

      const rewardDrop = hre.ethers.parseEther("27500");  // Convert 27500 to wei
      const stakeContractFactory = await hre.ethers.getContractFactory("RWANativeStake");
      const stakeContract = await stakeContractFactory.deploy(rewardDrop);

    
      return { stakeContract, owner, addr1, addr2 };
      
    }

    describe("Deployment", function(){

      it("Should deploy contract with correct initial parameters", async function () {

         
        // We use deployContractFixture to setup our environment, and then assert that
        // things went well

        const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
        const ONE_WEEK_IN_SECS = 7 * 24 * 60 * 60;
        const ONE_DAY_IN_SECS = 24 * 60 * 60;
          

        const { stakeContract, owner } = await loadFixture(deployContractFixture);

          
        expect(await stakeContract.treasury()).to.equal(0);
        expect(await stakeContract.totalStaked()).to.equal(0);
        expect(await stakeContract.totalStakers()).to.equal(0);

        expect(await stakeContract.lockTime()).to.equal(ONE_WEEK_IN_SECS);
        expect(await stakeContract.actionLimit()).to.equal(ONE_DAY_IN_SECS);

        expect(await stakeContract.government()).to.equal(owner.address);
        expect(await stakeContract.reductionPercent()).to.equal(3000);




      });


  });

  describe("Stake Operation", function(){

    it("Should allow owner to stake with flexible stake : 0 LOCK_PERIOD", async function () {
       
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("1"); // Staking 1 RWA

      await stakeContract.stake(0, { value: amountToStake });
      expect(await stakeContract.deposits(1)).to.equal(amountToStake);
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);



    });

    it("Should allow owner user stake with flexible stake ", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("1"); // Staking 1 RWA
      await stakeContract.connect(addr1).stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);


    });


    it("Should allow another user stake with flexible stake ", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("1"); // Staking 1 RWA
      await stakeContract.connect(addr1).stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);


    });

    it("Should allow another user do a fixed stake : 3 Months LOCK_PERIOD ", async function () {
      
      const ONE_MONTH = 30 * 24 * 60 * 60;

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA
      await stakeContract.connect(addr1).stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);

      // Advance the blockchain's timestamp by 3 months

      var currentBlock = await time.latestBlock();
      console.log("Current Block Now: %s", currentBlock);
      await time.increase(ONE_MONTH * 3);
      currentBlock = await time.latestBlock();
      console.log("Current Block Future: %s", currentBlock);

      // Now you can test the unstake function
      await stakeContract.connect(addr1).unstake();
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(0);
    });

    it("Should not allow user to stake with invalid lock period ", async function () {
       
      
    });
});

});