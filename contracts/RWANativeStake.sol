// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/**
  @title Staking implementation 
  @author tmortred, rony4d
  @notice implemented main interactive functions for staking
 */

contract RWANativeStake is Ownable, ReentrancyGuard {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct UserInfo {
    uint256[] stakingIds;
    uint256 lastStakeTime;
    uint256 rewardDebt;
  }

  uint256 constant MAX_BPS = 10_000;  // 10,000 Basis points which is 100% or 10000/100 = 100%
  uint256 constant WEEKS_OF_ONE_YEAR = 52;
  uint256 constant ONE_MONTH = 30 * 24 * 60 * 60;
  uint256 constant ONE_WEEK = 7 * 24 * 60 * 60;
  uint256 constant MAX_APR = 20_00; // 2,000 Basis points which is 20% or 2000/100 = 20%
  uint256 constant MIN_APR = 100;

  enum LOCK_PERIOD {
    NO_LOCK,
    THREE_MONTHS,
    SIX_MONTHS,
    NINE_MONTHS,
    TWELVE_MONTHS
  }

  address private _government;

  mapping (uint256 => uint256) public rewardDrop;
  mapping (address => UserInfo) public userInfo;
  mapping (uint256 => uint256) public deposits;
  mapping (uint256 => LOCK_PERIOD) public lockPeriod;
  mapping (uint256 => address) public depositor;
  mapping (uint256 => uint256) public stakeTime;
  mapping (address => uint256) public unclaimed;
  mapping (uint256 => address) public stakers;
  mapping (address => uint256) private stakerIndexMap;       // auxiliary mapping for stakers. it's not used externally

  uint256 public lastRewardWeek;
  uint256 immutable public startBlockTime;

  uint256[] public scoreLevels;
  mapping(uint256 => uint256) public rewardMultiplier;
  uint256 public counter;
  uint256 public reductionPercent = 3_000;
  uint256 public deductedBalance;
  uint256 public lockTime = ONE_WEEK;           // 7 days   
  uint256 public actionLimit = 24 * 3600;           // 1 day
  uint256 public maxActiveStake = 10;
  uint256 public totalStaked;
  uint256 public totalStakers;
  uint256 public treasury;
  mapping (uint256 => uint256) public totalWeightedScore;

  modifier onlyGovernment {
    require(_msgSender() == _government, "!government");
    _;
  }

  event Deposit(address indexed user, uint256 stakingId, uint256 amount, LOCK_PERIOD lockPeriod);
  event Withdraw(address indexed user, uint256 amount, LOCK_PERIOD lockPeriod, uint256 rewardAmount);
  event ForceUnlock(address indexed user, uint256 stakingId, uint256 amount, LOCK_PERIOD lockPeriod, uint256 offset);
  event RewardClaim(address indexed user, uint256 amount);
  event ReductionPercentChanged(uint256 oldReduction, uint256 newReduction);
  event GovernanceTransferred(address oldGov, address newGov);
  event LockTimeChanged(uint256 oldLockTime, uint256 newLockTime);
  event ActionLimitChanged(uint256 oldActionLimit, uint256 newActionLimit);
  event MaxActiveStakeUpdated(uint256 oldMaxActiveStake, uint256 newMaxActiveStake);
  event RewardAdded(uint256 added, uint256 treasury);
  event RewardWithdrawn(uint256 withdrawn, uint256 treasury);
  event RewardDropUpdated(uint256 rewardDrop, uint256 weekNumber);
  event DeductedBalanceWithdrawn(uint256 withdrawn);

  constructor(uint256 _rewardDrop) public {
    require(_rewardDrop != 0, "reward drop can't be zero");
    startBlockTime = block.timestamp;
    rewardDrop[0] = _rewardDrop;

    _government = _msgSender();

    scoreLevels.push(0);
    scoreLevels.push(500);
    scoreLevels.push(1000);
    scoreLevels.push(2000);
    scoreLevels.push(4000);
    scoreLevels.push(8000);
    scoreLevels.push(16000);
    scoreLevels.push(32000);
    scoreLevels.push(50000);
    scoreLevels.push(100000);
    rewardMultiplier[scoreLevels[0]] = 1000;
    rewardMultiplier[scoreLevels[1]] = 1025;
    rewardMultiplier[scoreLevels[2]] = 1050;
    rewardMultiplier[scoreLevels[3]] = 1100;
    rewardMultiplier[scoreLevels[4]] = 1200;
    rewardMultiplier[scoreLevels[5]] = 1400;
    rewardMultiplier[scoreLevels[6]] = 1800;
    rewardMultiplier[scoreLevels[7]] = 2600;
    rewardMultiplier[scoreLevels[8]] = 3500;
    rewardMultiplier[scoreLevels[9]] = 6000;
  }

  /**
    @notice
     a user can stake several times but only without lock period.
     locked staking is possible only one time for one wallet.
     locked staking and standard staking can't be combined.
    @param _lockPeriod enum value for representing lock period
   */
  function stake( LOCK_PERIOD _lockPeriod) external payable nonReentrant {
    // check if stake action valid
    require(msg.value > 0, "Cannot stake 0 RWA");

    uint256 _amount = msg.value;

    uint256 diff = block.timestamp.sub(userInfo[_msgSender()].lastStakeTime);
    require(diff > actionLimit, "staking too much in short period is not valid");
    uint256[] memory stakingIds = userInfo[_msgSender()].stakingIds;
    if (stakingIds.length != 0) {
      require(lockPeriod[stakingIds[0]] == LOCK_PERIOD.NO_LOCK && _lockPeriod == LOCK_PERIOD.NO_LOCK, "multi-staking works only for standard vault");
      require(stakingIds.length < maxActiveStake, "exceed maxActiveStake");
    }

    // update state variables
    counter = counter.add(1);
    if (stakingIds.length == 0) {
      stakerIndexMap[_msgSender()] = totalStakers;
      stakers[totalStakers] = _msgSender();
      totalStakers++;
    }
    
    deposits[counter] = _amount;
    totalStaked = totalStaked.add(_amount);
    depositor[counter] = _msgSender();
    stakeTime[counter] = block.timestamp;
    userInfo[_msgSender()].lastStakeTime = block.timestamp;
    lockPeriod[counter] = _lockPeriod;
    userInfo[_msgSender()].stakingIds.push(counter);

    // transfer tokens
    // token.safeTransferFrom(_msgSender(), address(this), _amount);

    emit Deposit(_msgSender(), counter, _amount, _lockPeriod);
  }

  /**
   * @notice
   *  withdraw tokens with reward gain
   *  users can't unstake partial amount
   */
  function unstake() external nonReentrant {
    // check if unstake action is valid
    require(userInfo[_msgSender()].stakingIds.length > 0, "no active staking");
    uint256 diff = block.timestamp.sub(userInfo[_msgSender()].lastStakeTime);
    require(diff > lockTime, "can't unstake within minimum lock time"); 
    uint256 stakingId = userInfo[_msgSender()].stakingIds[0];
    uint256 lock = uint256(lockPeriod[stakingId]).mul(3).mul(ONE_MONTH);
    require(diff > lock, "locked");
    
    // calculate the reward amount
    uint256 reward = _pendingReward(_msgSender()).sub(userInfo[_msgSender()].rewardDebt);
    if (reward > treasury) {
      unclaimed[_msgSender()] = reward.sub(treasury);
      reward = treasury;
      delete treasury;
    } else {
      treasury = treasury.sub(reward);
    }
    
    // transfer tokens to the _msgSender()  
    // uint256 stakeAmount = _getTotalStaked(_msgSender());
    // token.safeTransfer(_msgSender(), stakeAmount.add(reward));

    // Update to use native coin for unstaking
    uint256 stakeAmount = _getTotalStaked(_msgSender());
    payable(_msgSender()).transfer(stakeAmount.add(reward));

    // update the state variables
    totalStaked = totalStaked.sub(stakeAmount);
    delete userInfo[_msgSender()];
    
    uint256 csi = stakerIndexMap[_msgSender()];
    totalStakers--;
    stakers[csi] = stakers[totalStakers];
    stakerIndexMap[stakers[csi]] = csi;
    delete stakers[totalStakers];
    delete stakerIndexMap[_msgSender()];
    
    emit Withdraw(_msgSender(), stakeAmount, lockPeriod[stakingId], reward);
  }

  /**
   * @notice
   *  claim reward accumulated so far
   * @dev
   *  claimed reward amount is reflected when next claim reward or standard unstake action
   */
  function claimReward() external nonReentrant {
    require(treasury > 0, "reward pool is empty");
    
    uint256 claimed;
    if (unclaimed[_msgSender()] > 0) {
      require(unclaimed[_msgSender()] <= treasury, "insufficient");
      // token.safeTransfer(_msgSender(), unclaimed[_msgSender()]); 
      claimed = unclaimed[_msgSender()];
      // Update to use native coin for reward
      payable(_msgSender()).transfer(claimed);
      delete unclaimed[_msgSender()];
    } else {
      uint256 reward = _pendingReward(_msgSender()).sub(userInfo[_msgSender()].rewardDebt);
      require(reward > 0, "pending reward amount is zero");

      if (reward >= treasury) {
        reward = treasury;
        delete treasury;
      } else {
        treasury = treasury.sub(reward);
      }
      
      // token.safeTransfer(_msgSender(), reward);
      claimed = reward;
      // Update to use native coin for staking
      payable(_msgSender()).transfer(claimed);
      userInfo[_msgSender()].rewardDebt = userInfo[_msgSender()].rewardDebt.add(reward);
    }
    
    emit RewardClaim(_msgSender(), claimed);
  }

  /**
   * @notice 
   *  a user can unstake before lock time ends but original fund is 
   *  deducted by up to 30 percent proportional to the end of lockup
   * @dev can't call this function when lockup released
   * @param stakingId staking id to unlock
   */
  function forceUnlock(uint256 stakingId) external nonReentrant {
    // check if it is valid
    require(_msgSender() == depositor[stakingId], "!depositor");
    uint256 diff = block.timestamp.sub(stakeTime[stakingId]);
    require(diff > lockTime, "can't unstake within minimum lock time");

    uint256 lock = uint256(lockPeriod[stakingId]).mul(3).mul(ONE_MONTH);
    require(diff < lock, "unlocked status");
    uint256 offset = lock.sub(diff);
    //  deposits * 30% * offset / lock
    uint256 reduction = deposits[stakingId].mul(reductionPercent).div(MAX_BPS).mul(offset).div(lock);
    
    // token.safeTransfer(_msgSender(), deposits[stakingId].sub(reduction));

    // Update to use native coin for force unlock
    payable(_msgSender()).transfer(deposits[stakingId].sub(reduction));

    deductedBalance = deductedBalance.add(reduction);
    
    emit ForceUnlock(_msgSender(), stakingId, deposits[stakingId], lockPeriod[stakingId], offset);

    // update the state variables
    totalStaked = totalStaked.sub(deposits[stakingId]);
    delete deposits[stakingId];
    delete userInfo[_msgSender()];

    uint256 csi = stakerIndexMap[_msgSender()];
    totalStakers--;
    stakers[csi] = stakers[totalStakers];
    stakerIndexMap[stakers[csi]] = csi;
    delete stakers[totalStakers];
    delete stakerIndexMap[_msgSender()];
  }

  /**
   * @notice
   *  reflect the total weighted score calculated from the external script(off-chain) to the contract.
   *  this function supposed to be called every week.
   *  only government can call this function
   * @param _totalWeightedScore total weighted score
   * @param weekNumber the week counter
   */
  function updatePool(uint256 _totalWeightedScore, uint256 weekNumber) external onlyGovernment {
    require(weekNumber > lastRewardWeek, "invalid call");
    
    for (uint256 i = lastRewardWeek + 1; i <= weekNumber; i++) {
      totalWeightedScore[i-1] = _totalWeightedScore;
      if (i > 1 && rewardDrop[i-1] == 0) {
        rewardDrop[i-1] = rewardDrop[i-2].sub(rewardDrop[i-2].div(100));
      }
      
      uint256 _apr;
      if (totalStaked > 0) {
        _apr = rewardDrop[i-1].mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
      } else {
        _apr = MAX_APR;
      }
      
      if (_apr > MAX_APR) {
        rewardDrop[i-1] = totalStaked.mul(MAX_APR).div(WEEKS_OF_ONE_YEAR).div(MAX_BPS);
      } else if (_apr < MIN_APR) {
        rewardDrop[i-1] = totalStaked.mul(MIN_APR).div(WEEKS_OF_ONE_YEAR).div(MAX_BPS).add(1);
      }
    }

    lastRewardWeek = weekNumber;
  }

  //////////////////////////////////////
  ////        View functions        ////
  //////////////////////////////////////

  
  /**
   * @notice
   *  apr value from the staking logic model
   * @dev can't be over `MAX_APR`
   * @return _apr annual percentage rate
   */
  function apr() external view returns (uint256) {
    uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
    uint256 _apr;
    if (totalStaked == 0 || current == 0) {
      _apr = MAX_APR;
    } else {
      _apr = rewardDrop[current - 1].mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
    }
    
    return _apr;
  }

  function getLengthOfStakers() external view returns (uint256) {
    return totalStakers;
  }

  function getTotalStaked(address user) external view returns (uint256) {
    return _getTotalStaked(user);
  }

  function getStakingIds(address user) external view returns (uint256[] memory) {
    return userInfo[user].stakingIds;
  }

  function getStakingInfo(uint256 stakingId) external view returns (address, uint256, uint256, LOCK_PERIOD) {
    return (depositor[stakingId], deposits[stakingId], stakeTime[stakingId], lockPeriod[stakingId]);
  }

  function getWeightedScore(address _user, uint256 weekNumber) external view returns (uint256) {
    return _getWeightedScore(_user, weekNumber);
  }

  function pendingReward(address _user) external view returns (uint256) {
    if (unclaimed[_user] > 0) {
      return unclaimed[_user];
    } else {
      return _pendingReward(_user).sub(userInfo[_user].rewardDebt);
    }
  }

  function government() external view returns (address) {
    return _government;
  }

  //////////////////////////////
  ////    Admin functions   ////
  //////////////////////////////

  function addReward() external payable onlyOwner {
    // require(IERC20(token).balanceOf(_msgSender()) >= amount, "not enough tokens to deliver");
    // IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
    // treasury = treasury.add(amount);

    // Update to use native coin for adding reward

    require(msg.value > 0, "Cannot add 0 RWA reward");

    uint256 amount = msg.value;

    treasury = treasury.add(amount);

    emit RewardAdded(amount, treasury);
  }

  function withdrawReward(uint256 amount) external onlyOwner {
    if (amount > treasury) {
      amount = treasury;
    }
    // IERC20(token).safeTransfer(_msgSender(), amount);
    // Update to use native coin for withdrawing reward
    payable(_msgSender()).transfer(amount);

    treasury = treasury.sub(amount);

    emit RewardWithdrawn(amount, treasury);
  }

  function withdrawDeductedBalance() external onlyOwner {
    require(deductedBalance > 0, "no balance to withdraw");
    // IERC20(token).safeTransfer(_msgSender(), deductedBalance);
    payable(_msgSender()).transfer(deductedBalance);
    emit DeductedBalanceWithdrawn(deductedBalance);
    delete deductedBalance;
  }

  function setLockTime(uint256 _lockTime) external onlyOwner {
    require(_lockTime != 0, "!zero");
    emit LockTimeChanged(lockTime, _lockTime);
    lockTime = _lockTime;
  }

  function setReductionPercent(uint256 _reductionPercent) external onlyOwner {
    require(_reductionPercent < MAX_BPS, "overflow");
    emit ReductionPercentChanged(reductionPercent, _reductionPercent);
    reductionPercent = _reductionPercent;
  }

  function setRewardDrop(uint256 _rewardDrop) external onlyOwner {
    require(totalStaked > 0, "no staked tokens");
    uint256 _apr = _rewardDrop.mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
    require(_apr >= MIN_APR, "not meet MIN APR");
    require(_apr <= MAX_APR, "not meet MAX APR");
    uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
    rewardDrop[current] = _rewardDrop;

    emit RewardDropUpdated(_rewardDrop, current);
  }

  function transferGovernance(address _newGov) external onlyOwner {
    require(_newGov != address(0), "new governance is the zero address");
    emit GovernanceTransferred(_government, _newGov);
    _government = _newGov;
  }

  function setActionLimit(uint256 _actionLimit) external onlyOwner {
    require(_actionLimit != 0, "!zero");
    emit ActionLimitChanged(actionLimit, _actionLimit);
    actionLimit = _actionLimit;
  }

  function setMaxActiveStake(uint256 _maxActiveStake) external onlyOwner {
    require(_maxActiveStake !=0, "!zero");
    emit MaxActiveStakeUpdated(maxActiveStake, _maxActiveStake);
    maxActiveStake = _maxActiveStake;
  }

  /////////////////////////////////
  ////    Internal functions   ////
  /////////////////////////////////

  // get the total staked amount of user
  function _getTotalStaked(address user) internal view returns (uint256) {
    uint256 _totalStaked;
    uint256[] memory stakingIds = userInfo[user].stakingIds;
    // the length of `stakingIds` is limited to `maxActiveStake` to avoid too much gas consumption.
    for (uint i; i < stakingIds.length; i++) {
      uint256 stakingId = stakingIds[i];
      _totalStaked = _totalStaked.add(deposits[stakingId]);
    }

    return _totalStaked;
  }

  function _pendingReward(address _user) internal view returns (uint256) {
    uint256 reward;
    uint256 firstStakingId = userInfo[_user].stakingIds[0];
    uint256 firstStakeWeek = stakeTime[firstStakingId].sub(startBlockTime).div(ONE_WEEK);
    uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
    for (uint i = firstStakeWeek; i <= current; i++) {
      uint256 weightedScore = _getWeightedScore(_user, i);
      if (totalWeightedScore[i] != 0) {
        reward = reward.add(rewardDrop[i].mul(weightedScore).div(totalWeightedScore[i]));
      }
    }
    return reward;
  }

  function _getWeightedScore(address _user, uint256 weekNumber) internal view returns (uint256) {
    // calculate the basic score
    uint256 score;
    uint256[] memory stakingIds = userInfo[_user].stakingIds;
    // the length of `stakingIds` is limited to `maxActiveStake` to avoid too much gas consumption.
    for (uint i; i < stakingIds.length; i++) {
      uint256 stakingId = stakingIds[i];
      uint256 _score = getScore(stakingId, weekNumber);
      score = score.add(_score);
    }

    // calculate the weighted score
    if (score == 0) return 0;

    uint256 weightedScore;
    for (uint i; i < scoreLevels.length; i++) {
      if (score > scoreLevels[i]) {
        weightedScore = score.mul(rewardMultiplier[scoreLevels[i]]);
      } else {
        return weightedScore;
      }
    }

    return weightedScore;

  }

  function getScore(uint256 stakingId, uint256 weekNumber) internal view returns (uint256) {
    uint256 score;
    uint256 stakeWeek = stakeTime[stakingId].sub(startBlockTime).div(ONE_WEEK);
    if (stakeWeek > weekNumber) return 0;
    uint256 diff = weekNumber.sub(stakeWeek) > WEEKS_OF_ONE_YEAR ? WEEKS_OF_ONE_YEAR : weekNumber.sub(stakeWeek);
    uint256 lockScore = deposits[stakingId].mul(uint256(lockPeriod[stakingId])).mul(3).div(12);
    score = deposits[stakingId].mul(diff + 1).div(WEEKS_OF_ONE_YEAR).add(lockScore);
    if (score > deposits[stakingId]) {
      score = deposits[stakingId].div(1e18);
    } else {
      score = score.div(1e18);
    }

    return score;
  }
}