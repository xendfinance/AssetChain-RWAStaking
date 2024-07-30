import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";
  import { ethers, upgrades } from "hardhat";

  
  // Import upgrades from @openzeppelin/hardhat-upgrades

  
describe("RWA Native Stake Contract", function(){
  const ONE_MONTH = 30 * 24 * 60 * 60;
  const ONE_WEEK =   7 * 24 * 60 * 60;
  const ONE_DAY =   24 * 60 * 60;
  const INITIAL_REWARD_DROP = 27500;
  const MAX_BPS = 10_000n;
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.

    async function deployContractFixture(){


      const [owner, addr1, addr2] = await hre.ethers.getSigners();
    
      const rewardDrop = hre.ethers.parseEther(INITIAL_REWARD_DROP.toString());  // Convert 27500 to wei
      const stakeContractFactory = await hre.ethers.getContractFactory("RWANativeStake");

      const stakeContract = await upgrades.deployProxy(stakeContractFactory, [rewardDrop,owner.address], {initializer: "initialize"});

      // const stakeContract = await stakeContractFactory.deploy(rewardDrop,owner);

      console.log("RWANativeStake deployed to:", stakeContract.address);

      return { stakeContract, owner, addr1, addr2 };
      
    }

    async function oracleCall()
    {
      console.log("Oracle Start");

      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);

      const lastRewardWeek = await stakeContract.lastRewardWeek();
  
      //  Oracle Section - To be called 7 days after staking has happened 
      const START_BLOCK_TIME = await stakeContract.startBlockTime();
      const lastWeekNumber = lastRewardWeek;
  
      const currentBlock = await time.latestBlock();
      const block = await hre.ethers.provider.getBlock(currentBlock);
      const currentBlockTime = block?.timestamp;
      const currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
  
      const lengthOfStakers = await stakeContract.getLengthOfStakers();
  
      console.log("lengthOfStakers: %s", lengthOfStakers);

      for(let i = lastWeekNumber + 1n; i <= currentWeek; i++){
        let totalScore = 0n;
        
        for(let j = 0; j < lengthOfStakers; j++)
          {
            const user = await stakeContract.stakers(j);
            const score = await stakeContract.getWeightedScore(user, i);

            //  add user to db
            //  add user's score

            totalScore = totalScore + score;
          }
  
          console.log("Total Score: %s", totalScore);
          // call update pool function per week
          await stakeContract.updatePool(totalScore, i);

      }
  
      console.log("Start BlockTime: %s, Current Block: %s, Current Block Time: %s, Current Week ", Number(START_BLOCK_TIME),  currentBlock, currentBlockTime, currentWeek);

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
      // console.log("Staked Amount: %s RWA, Deducted Balance: %s",hre.ethers.formatEther(amountToStake),hre.ethers.formatEther(deductedBalance));

      expect(deductedBalance).to.be.greaterThan(0);
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(0);

    });

  });


  describe("APR Operation", async function(){

    it("Should calculate APR change after one week and oracle call", async function(){
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      var ownerBalance = await hre.ethers.provider.getBalance(owner.getAddress());

      console.log("Owner Balance: %s ",hre.ethers.formatEther(ownerBalance));

      //  1. Stake
      const amountToStake = hre.ethers.parseEther("9000"); // Staking 9,000 RWA
      await stakeContract.stake(0, { value: amountToStake });
      expect(await stakeContract.deposits(1)).to.equal(amountToStake);
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);
      expect(await stakeContract.totalStaked()).to.equal(amountToStake);



      //  2. Before oracle is called, check initial reward drop of current week, lastrewardweek, current week,  total weighted score of lastreward week, apr, staking score
      const START_BLOCK_TIME = await stakeContract.startBlockTime();
      var lastRewardWeek = await stakeContract.lastRewardWeek();

  
      var currBlock = await time.latestBlock();
      var block = await hre.ethers.provider.getBlock(currBlock);
      var currentBlockTime = block?.timestamp;
      var currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
      var lastWeekNumber = currentWeek > 0n ? currentWeek : 0n;

      const firstRewardDrop = await stakeContract.rewardDrop(0);
      var totalWeightedScore = await stakeContract.totalWeightedScore(lastRewardWeek);
      var apr = await stakeContract.apr();
      var initialUserStakingScore = await stakeContract.getWeightedScore(owner.address, currentWeek);

      console.log("First Reward Drop: %s ",hre.ethers.formatEther(firstRewardDrop));


      expect(firstRewardDrop).to.equal(hre.ethers.parseEther(INITIAL_REWARD_DROP.toString()));
      expect(currentWeek).to.equal(0);
      expect(lastRewardWeek).to.equal(0);
      expect(totalWeightedScore).to.equal(0);
      expect(apr).to.equal(2000);
      expect(initialUserStakingScore).to.greaterThan(0);

      //  3. Advance blockchain by one week  and then trigger the oracle
      var currentBlock = await time.latestBlock();
      await time.increase(ONE_WEEK);
      currentBlock = await time.latestBlock();

      block = await hre.ethers.provider.getBlock(currentBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));

      expect(currentWeek).to.equal(1);
      
      //  4. Call Oracle - To be called 7 days after staking has happened 
      
      const lengthOfStakers = await stakeContract.getLengthOfStakers();
  
      for(let i = lastWeekNumber + 1n; i <= currentWeek; i++){
        let totalScore = 0n;
        
        for(let j = 0; j < lengthOfStakers; j++)
          {
            const user = await stakeContract.stakers(j);
            const score = await stakeContract.getWeightedScore(user, i);

            //  add user to db
            //  add user's score

            totalScore = totalScore + score;
          }
  
          // call update pool function per week
          await stakeContract.updatePool(totalScore, i);

      }

      //  5. After oracle is called, check reward drop current week, lastrewardweek, current week, total weighted score of lastreward week, apr 

      lastRewardWeek = await stakeContract.lastRewardWeek();  
      currBlock = await time.latestBlock();
      block = await hre.ethers.provider.getBlock(currBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
      lastWeekNumber = currentWeek - 1n;                   //  
      var currentWeekRewardDrop = await stakeContract.rewardDrop(currentWeek);
      var lastWeekRewardDrop = await stakeContract.rewardDrop(lastWeekNumber);
      totalWeightedScore = await stakeContract.totalWeightedScore(lastWeekNumber);
      var newapr = await stakeContract.apr() ;
      var finalUserStakingScore = await stakeContract.getWeightedScore(owner.address, currentWeek);

      console.log("Last Reward Week: %s, Current Week:%s, Current Week Reward Drop: %s,  Last Week Reward Drop: %s , Total Weighted Score: %s, APR: %s",
      lastRewardWeek,currentWeek,currentWeekRewardDrop,hre.ethers.formatEther(lastWeekRewardDrop),totalWeightedScore,newapr);


      expect(currentWeek).to.equal(1);
      expect(totalWeightedScore).to.greaterThan(0);
      expect(newapr).to.lessThan(2000);
      expect(finalUserStakingScore).to.greaterThan(initialUserStakingScore);      // final should be greater since time has passed between staking time and now


    });

    it("Should calculate APR change after one week , oracle call , updating reward drop , another week and another oracle call ", async function(){
      
      const { stakeContract, owner, addr1 } = await loadFixture(deployContractFixture);
      var ownerBalance = await hre.ethers.provider.getBalance(owner.getAddress());

      console.log("Owner Balance: %s ",hre.ethers.formatEther(ownerBalance));

      //  1. Stake
      const amountToStake = hre.ethers.parseEther("9000"); // Staking 9,000 RWA
      await stakeContract.stake(0, { value: amountToStake });
      expect(await stakeContract.deposits(1)).to.equal(amountToStake);
      expect(await stakeContract.getStakingIds(owner.address)).to.have.lengthOf(1);
      expect(await stakeContract.totalStaked()).to.equal(amountToStake);


      //  2. Before oracle is called, check initial reward drop of current week, lastrewardweek, current week,  total weighted score of lastreward week, apr 
      const START_BLOCK_TIME = await stakeContract.startBlockTime();
      var lastRewardWeek = await stakeContract.lastRewardWeek();

  
      var currBlock = await time.latestBlock();
      var block = await hre.ethers.provider.getBlock(currBlock);
      var currentBlockTime = block?.timestamp;
      var currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
      var lastWeekNumber = currentWeek > 0n ? currentWeek : 0n;

      const firstRewardDrop = await stakeContract.rewardDrop(0);
      var totalWeightedScore = await stakeContract.totalWeightedScore(lastRewardWeek);
      var apr = await stakeContract.apr();

      console.log("First Reward Drop: %s ",hre.ethers.formatEther(firstRewardDrop));


      expect(firstRewardDrop).to.equal(hre.ethers.parseEther(INITIAL_REWARD_DROP.toString()));
      expect(currentWeek).to.equal(0);
      expect(lastRewardWeek).to.equal(0);
      expect(totalWeightedScore).to.equal(0);
      expect(apr).to.equal(2000);


      //  3. Advance blockchain by one week  and then trigger the oracle
      var currentBlock = await time.latestBlock();
      await time.increase(ONE_WEEK);
      currentBlock = await time.latestBlock();

      block = await hre.ethers.provider.getBlock(currentBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));

      expect(currentWeek).to.equal(1);
      
      //  4. Call Oracle - To be called 7 days after staking has happened 
      
      var lengthOfStakers = await stakeContract.getLengthOfStakers();
  
      for(let i = lastWeekNumber + 1n; i <= currentWeek; i++){
        let totalScore = 0n;
        
        for(let j = 0; j < lengthOfStakers; j++)
          {
            const user = await stakeContract.stakers(j);
            const score = await stakeContract.getWeightedScore(user, i);

            //  add user to db
            //  add user's score

            totalScore = totalScore + score;
          }
  
          // call update pool function per week
          await stakeContract.updatePool(totalScore, i);

      }

      //  5. After oracle is called, check reward drop current week, lastrewardweek, current week, total weighted score of lastreward week, apr 

      lastRewardWeek = await stakeContract.lastRewardWeek();  
      currBlock = await time.latestBlock();
      block = await hre.ethers.provider.getBlock(currBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
      lastWeekNumber = currentWeek - 1n;                   //  
      var currentWeekRewardDrop = await stakeContract.rewardDrop(currentWeek);
      var lastWeekRewardDrop = await stakeContract.rewardDrop(lastWeekNumber);
      totalWeightedScore = await stakeContract.totalWeightedScore(lastWeekNumber);
      var newapr = await stakeContract.apr() ;


      console.log("Last Reward Week: %s, Current Week:%s, Current Week Reward Drop: %s,  Last Week Reward Drop: %s , Total Weighted Score: %s, APR: %s",
      lastRewardWeek,currentWeek,currentWeekRewardDrop,hre.ethers.formatEther(lastWeekRewardDrop),totalWeightedScore,newapr);


      expect(currentWeek).to.equal(1);
      expect(totalWeightedScore).to.greaterThan(0);
      expect(newapr).to.lessThan(2000);


      //  6. Stake again with another user

      const addr1amountToStake = hre.ethers.parseEther("9000"); // Staking 9,000 RWA
      await stakeContract.connect(addr1).stake(0, { value: addr1amountToStake });

      expect(await stakeContract.deposits(2)).to.equal(addr1amountToStake);
      expect(await stakeContract.getStakingIds(addr1.address)).to.have.lengthOf(1);
      expect(await stakeContract.totalStaked()).to.equal(amountToStake+addr1amountToStake);


      //  6. Update the reward drop

      await stakeContract.setRewardDrop(hre.ethers.parseEther("60"));         //  set the reward drop to an amount that will fall within MIN_APR and MAX_APR. This reward drop should be small because this is just one week into staking program with a small amount staked.
      var updatedCurrentWeekRewardDrop = await stakeContract.rewardDrop(currentWeek);
      expect(updatedCurrentWeekRewardDrop).to.greaterThan(currentWeekRewardDrop);



      //  7. Advance blockchain for another one week

      currentBlock = await time.latestBlock();
      await time.increase(ONE_WEEK);
      currentBlock = await time.latestBlock();

      block = await hre.ethers.provider.getBlock(currentBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));

      expect(currentWeek).to.equal(2);

      //  8. Call Oracle Again

      lengthOfStakers = await stakeContract.getLengthOfStakers();
  
      lastWeekNumber = currentWeek - 1n;

      for(let i = lastWeekNumber + 1n; i <= currentWeek; i++){
        let totalScore = 0n;
        
        for(let j = 0; j < lengthOfStakers; j++)
          {
            const user = await stakeContract.stakers(j);
            const score = await stakeContract.getWeightedScore(user, i);

            //  add user to db
            //  add user's score

            totalScore = totalScore + score;
          }
  
          // call update pool function per week
          await stakeContract.updatePool(totalScore, i);

      }

      expect(lengthOfStakers).to.equal(2);



      //  9. Get the APR : After oracle is called, check reward drop current week, lastrewardweek, current week, total weighted score of lastreward week, apr 

      lastRewardWeek = await stakeContract.lastRewardWeek();  
      currBlock = await time.latestBlock();
      block = await hre.ethers.provider.getBlock(currBlock);
      currentBlockTime = block?.timestamp;
      currentWeek = BigInt(Math.floor(Number(BigInt(currentBlockTime || 0) - START_BLOCK_TIME) / Number(BigInt(ONE_WEEK))));
      lastWeekNumber = currentWeek - 1n;                   //  
      var currentWeekRewardDrop = await stakeContract.rewardDrop(currentWeek);
      var lastWeekRewardDrop = await stakeContract.rewardDrop(lastWeekNumber);
      totalWeightedScore = await stakeContract.totalWeightedScore(lastWeekNumber);
      var newapr = await stakeContract.apr() ;


      console.log("After 2 weeks Oracle call: Last Reward Week: %s, Current Week:%s, Current Week Reward Drop: %s,  Last Week Reward Drop: %s , Total Weighted Score: %s, APR: %s",
      lastRewardWeek,currentWeek,currentWeekRewardDrop,hre.ethers.formatEther(lastWeekRewardDrop),totalWeightedScore,newapr);


      expect(currentWeek).to.equal(2);
      expect(totalWeightedScore).to.greaterThan(0);
      expect(newapr).to.lessThan(2000);
      expect(lastWeekRewardDrop).to.equal(hre.ethers.parseEther("60"));      //  Reward drop should equal what we set above


      //  Final Note: 
      //  It is important to understand that  the update of the reward drop actually reduced the overall APR which is correct
      //  The APR will only take effect after the updatepool function is called
      //  The reward drop dropped drastically from 27,500 to 60 because we specified a 20% MAX_APR, two stakers and then only 2 weeks out of the entire year. 
      //  This means that for the first 27,500 was extremely high but it not a problem as this amount will still be distributed to the stakers


    });


  });
  describe("Claim Reward Operation", function(){

  })


  
});