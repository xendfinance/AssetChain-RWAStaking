import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";

  
describe("RWA Native Stake Contract", function(){
  const ONE_MONTH = 30 * 24 * 60 * 60;
  const ONE_WEEK =   7 * 24 * 60 * 60;
  const ONE_DAY =   24 * 60 * 60;

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

    it("Should allow user1 stake with flexible stake ", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("1"); // Staking 1 RWA
      await stakeContract.connect(addr1).stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);


    });

    it("Should allow another user do a fixed stake : 3 Months LOCK_PERIOD ", async function () {
      

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA
      await stakeContract.connect(addr1).stake(1, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);

      // Advance the blockchain's timestamp by 3 months

      var currentBlock = await time.latestBlock();
      await time.increase(ONE_MONTH * 3);
      currentBlock = await time.latestBlock();

      // Now you can test the unstake function
      await stakeContract.connect(addr1).unstake();
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(0);
    });

    it("Should not allow user to stake with invalid lock period ", async function () {
       
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amount = hre.ethers.parseEther('1.0');
      const invalidLockPeriod = 999; // assume 999 is not a valid lock period

      await expect(stakeContract.connect(owner).stake(invalidLockPeriod, { value: amount })).to.be.rejected;

      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(0);

    });


    
});

  describe("Unstake Operation", function(){

    it("Should allow owner to unstake with flexible stake : 0 LOCK_PERIOD", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);

      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA

      await stakeContract.stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);
      
      // Advance the blockchain's timestamp by one week to allow unstake after minimum lock time of one week

      var currentBlock = await time.latestBlock();
      await time.increase(ONE_WEEK);
      currentBlock = await time.latestBlock();

      // Now you can test the unstake function
      await stakeContract.connect(owner).unstake();
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(0);


    });

    it("Should not allow owner to unstake within minimum lock time on flexible stake : 0 LOCK_PERIOD", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);

      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA

      await stakeContract.stake(0, { value: amountToStake });
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);
      
      // Now you can test the unstake function
      await expect(stakeContract.connect(owner).unstake()).to.be.revertedWith("can't unstake within minimum lock time");
      //  Stake is still active so stakingIDs will still be 1
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1); 


    });


    it("Should not allow owner to unstake within fixed stake period : 3 Months LOCK_PERIOD", async function () {
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);

      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA

      await stakeContract.stake(1, { value: amountToStake });
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);
      
      // Now you can test the unstake function
      await expect(stakeContract.connect(owner).unstake()).to.be.revertedWith("can't unstake within minimum lock time");
      //  Stake is still active so stakingIDs will still be 1
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1); 


    });

    it("Should allow user to unstake after fixed stake is completed : 6 Months LOCK_PERIOD ", async function () {
      

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA
      await stakeContract.connect(addr1).stake(2, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);

      // Advance the blockchain's timestamp by 6 months

      var currentBlock = await time.latestBlock();
      await time.increase(ONE_MONTH * 6);
      currentBlock = await time.latestBlock();

      // Now you can test the unstake function
      await stakeContract.connect(addr1).unstake();
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(0);


    });

    it("Should allow owner to force unlock 3 months into 6 months of fixed staking and slash stake amount ", async function () {
      

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      const amountToStake = hre.ethers.parseEther("10"); // Staking 10 RWA
      await stakeContract.connect(addr1).stake(2, { value: amountToStake });
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);

      // Advance the blockchain's timestamp by 3 months

      var currentBlock = await time.latestBlock();
      await time.increase(ONE_MONTH * 3);
      currentBlock = await time.latestBlock();

      // Now you can test the unstake function
      await expect(stakeContract.connect(addr1).unstake()).to.be.revertedWith("locked");
      
      //  Force Unlock staking ID 1
      await stakeContract.connect(addr1).forceUnlock(1);

      const deductedBalance = await stakeContract.deductedBalance();
      console.log("Staked Amount: %s RWA, Deducted Balance: %s",hre.ethers.formatEther(amountToStake),hre.ethers.formatEther(deductedBalance));

      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(0);

    });

  });

  describe("Claim Reward Operation", function(){

    it("Should should update reward pool ", async function () {
      
      const totalWeightedScoreForWeekFromOracle = 10000;
      const weekNumberFromOracle = 1;

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      expect(await stakeContract.lastRewardWeek()).to.equal(0);
      var totalWeightedScore = await stakeContract.totalWeightedScore(0);
      var rewardDrop = await stakeContract.rewardDrop(0);
      var apr = await stakeContract.apr();

      const amountToStake = hre.ethers.parseEther("1000"); // Staking 1000 RWA

      await stakeContract.stake(1, { value: amountToStake });
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);


      // console.log("Before Update Pool Call From Oracle: Total Weighted Score: %s, Reward Drop: %s, APR: %s", totalWeightedScore, hre.ethers.formatEther(rewardDrop), apr );


      await stakeContract.connect(owner).updatePool(totalWeightedScoreForWeekFromOracle,weekNumberFromOracle);
      await stakeContract.connect(owner).updatePool(totalWeightedScoreForWeekFromOracle+5000,weekNumberFromOracle+1);

      expect(await stakeContract.lastRewardWeek()).to.equal(2);
      totalWeightedScore = await stakeContract.totalWeightedScore(0);
      rewardDrop = await stakeContract.rewardDrop(1);
      apr = await stakeContract.apr();



      // console.log("After Update Pool Call From Oracle: Total Weighted Score: %s, Reward Drop: %s, APR: %s", totalWeightedScore, hre.ethers.formatEther(rewardDrop), apr );

    });

  })
  
});