// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
  @title Staking implementation 
  @notice implemented main interactive functions for staking
 */
contract RWANativeStake is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

  struct UserInfo {
    uint256[] stakingIds;
    uint256 lastStakeTime;
    uint256 rewardDebt;
  }

  uint256 public constant MAX_BPS = 10_000;  // 10,000 Basis points which is 100% or 10000/100 = 100%
  uint256 public constant WEEKS_OF_ONE_YEAR = 52;
  uint256 public constant ONE_MONTH = 30 * 24 * 60 * 60;
  uint256 public constant ONE_WEEK = 7 * 24 * 60 * 60;
  uint256 public constant MAX_APR = 20_00; // 2,000 Basis points which is 20% or 2000/100 = 20%
  uint256 public constant MIN_APR = 100;

  enum LOCK_PERIOD {
    NO_LOCK,
    THREE_MONTHS,
    SIX_MONTHS,
    NINE_MONTHS,
    TWELVE_MONTHS
  }

  address private _government;
  address public multiSigWallet;

  mapping (uint256 => uint256) public rewardDrop;
  mapping (address => UserInfo) public userInfo;
  mapping (uint256 => uint256) public deposits;
  mapping (uint256 => LOCK_PERIOD) public lockPeriod;
  mapping (uint256 => address) public depositor;
  mapping (uint256 => uint256) public stakeTime;
  mapping (address => uint256) public unclaimed;
  mapping (uint256 => address) public stakers;
  mapping (address => uint256) private _stakerIndexMap;       // auxiliary mapping for stakers. it's not used externally

  uint256 public lastRewardWeek;
  uint256 public startBlockTime;

  uint256[] public scoreLevels;
  mapping(uint256 => uint256) public rewardMultiplier;
  uint256 public counter;
  uint256 public reductionPercent;
  uint256 public deductedBalance;
  uint256 public lockTime;           
  uint256 public actionLimit;           
  uint256 public maxActiveStake;
  uint256 public totalStaked;
  uint256 public totalStakers;
  uint256 public treasury;
  uint256 public MaxWeeks;

  mapping (uint256 => uint256) public totalWeightedScore;

 

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

  // Custom errors
  error StakedAmountCannotBeZero();
  error MultipleStakingTypesNotAllowed();
  error ExceededMaxActiveStake();
  error ExceededActionLimit();
  error CannotUnstakeWithinMinimumLockTime();
  error StakingIsLocked();
  error TransferFailed();
  error CannotClaimZeroReward();
  error StakingIsUnlocked();
  error LockTimeCannotBeZero();
  error TreasuryIsEmpty();
  error NotDepositor(address sender);
  error NotGovernment(address sender);

  error WeekNumberCannotBeLessThanOrEqualToLastRewardWeek(uint256 newWeek, uint256 lastUpdated);
  error NotOwner(address sender);
  error AmountCannotBeZero();
  error CannotAddZeroReward();
  error ReductionPercentTooHigh();
  error APRIsNotBetweenMinumumandMaximumAPR();
  error NotMultiSig(address sender);
  error DeductedBalanceIsZero();
  error NewValueCannotBeZero();
  error NoStakedTokens();
  error NewGovernmentAddressCannotBeZero();
  error RewardDropCannotBeZero();
  error MultiSigWalletCannotBeZeroAddress();


  function initialize(uint256 _rewardDrop, address _multiSigWallet) public initializer {
    if (_rewardDrop == 0) revert RewardDropCannotBeZero();
    if (_multiSigWallet == address(0)) revert MultiSigWalletCannotBeZeroAddress();
    
    __Ownable_init(_msgSender()); // Initialize Ownable with the contract deployer
    __ReentrancyGuard_init(); // No arguments needed for ReentrancyGuard
    startBlockTime = block.timestamp;
    rewardDrop[0] = _rewardDrop;

    _government = _msgSender();
    multiSigWallet = _multiSigWallet;

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

    reductionPercent = 3_000;
    lockTime = ONE_WEEK;           // 7 days   
    actionLimit = 24 * 3600;           // 1 day
    maxActiveStake = 10;
    MaxWeeks = 52; // This sets a limit to the maximum number of weeks that can be used to calculate rewards to prevent consuming excess gas and failing the transaction when gas is higher than max block gas
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
    if (msg.value == 0) revert StakedAmountCannotBeZero();

    uint256 _amount = msg.value;

    uint256 diff = block.timestamp - userInfo[_msgSender()].lastStakeTime;
    if (diff <= actionLimit) revert ExceededActionLimit();
    uint256[] memory stakingIds = userInfo[_msgSender()].stakingIds;
    if (stakingIds.length != 0) {
      if (lockPeriod[stakingIds[0]] != LOCK_PERIOD.NO_LOCK || _lockPeriod != LOCK_PERIOD.NO_LOCK) {
        revert MultipleStakingTypesNotAllowed();
      }
      if (stakingIds.length >= maxActiveStake) {
        revert ExceededMaxActiveStake();
      }
    }

    // update state variables
    counter++;
    if (stakingIds.length == 0) {
      _stakerIndexMap[_msgSender()] = totalStakers;
      stakers[totalStakers] = _msgSender();
      totalStakers++;
    }
    
    deposits[counter] = _amount;
    totalStaked += _amount;
    depositor[counter] = _msgSender();
    stakeTime[counter] = block.timestamp;
    userInfo[_msgSender()].lastStakeTime = block.timestamp;
    lockPeriod[counter] = _lockPeriod;
    userInfo[_msgSender()].stakingIds.push(counter);

    emit Deposit(_msgSender(), counter, _amount, _lockPeriod);
  }

  /**
   * @notice
   *  withdraw tokens with reward gain
   *  users can't unstake partial amount
   */
  function unstake() external nonReentrant {
    // check if unstake action is valid
    if (userInfo[_msgSender()].stakingIds.length == 0) revert NoStakedTokens();
    uint256 diff = block.timestamp - userInfo[_msgSender()].lastStakeTime;
    if (diff <= lockTime) revert CannotUnstakeWithinMinimumLockTime(); 
    uint256 stakingId = userInfo[_msgSender()].stakingIds[0];
    uint256 lock = uint256(lockPeriod[stakingId]) * 3 * ONE_MONTH;
    if (diff <= lock) revert StakingIsLocked();
    
    // calculate the reward amount
    uint256 reward = _pendingReward(_msgSender()) - userInfo[_msgSender()].rewardDebt;
    if (reward > treasury) {
      unclaimed[_msgSender()] = reward - treasury;
      reward = treasury;
      treasury = 0;
    } else {
      treasury -= reward;
    }
    
    // transfer tokens to the _msgSender()  
    uint256 stakeAmount = _getTotalStaked(_msgSender());
    (bool success, ) = payable(_msgSender()).call{value: stakeAmount + reward}("");
    if (!success) revert TransferFailed();

    // update the state variables
    totalStaked -= stakeAmount;
    delete userInfo[_msgSender()];
    
    uint256 csi = _stakerIndexMap[_msgSender()];
    totalStakers--;
    stakers[csi] = stakers[totalStakers];
    _stakerIndexMap[stakers[csi]] = csi;
    delete stakers[totalStakers];
    delete _stakerIndexMap[_msgSender()];
    
    emit Withdraw(_msgSender(), stakeAmount, lockPeriod[stakingId], reward);
  }

  /**
   * @notice
   *  claim reward accumulated so far
   * @dev
   *  claimed reward amount is reflected when next claim reward or standard unstake action
   */
  function claimReward() external nonReentrant {
    if (treasury == 0) revert TreasuryIsEmpty();
    
    // Check if the user has any staked tokens
    if (userInfo[_msgSender()].stakingIds.length == 0) {
        revert NoStakedTokens();
    }

    uint256 claimed;
    uint256 reward = _pendingReward(_msgSender()) - userInfo[_msgSender()].rewardDebt;

    if (unclaimed[_msgSender()] > 0) {
      reward += unclaimed[_msgSender()];
      delete unclaimed[_msgSender()];
    }

    // Check if the reward is zero and revert if so
    if (reward == 0) revert CannotClaimZeroReward(); 

    if (reward > treasury) {
      claimed = treasury;
      unclaimed[_msgSender()] = reward - treasury;
      treasury = 0;
    } else {
      claimed = reward;
      treasury -= reward;
    }

    (bool success, ) = payable(_msgSender()).call{value: claimed}("");
    if (!success) revert TransferFailed();

    userInfo[_msgSender()].rewardDebt += claimed;

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
    if (_msgSender() != depositor[stakingId]) revert NotDepositor(_msgSender());
    uint256 diff = block.timestamp - stakeTime[stakingId];
    if (diff <= lockTime) revert CannotUnstakeWithinMinimumLockTime();

    uint256 lock = uint256(lockPeriod[stakingId]) * 3 * ONE_MONTH;
    if (diff >= lock) revert StakingIsUnlocked();
    uint256 offset = lock - diff;
    //  deposits * 30% * offset / lock
    uint256 reduction = deposits[stakingId] * reductionPercent / MAX_BPS * offset / lock;
    
    (bool success, ) = payable(_msgSender()).call{value: deposits[stakingId] - reduction}("");
    if (!success) revert TransferFailed();

    deductedBalance += reduction;
    
    emit ForceUnlock(_msgSender(), stakingId, deposits[stakingId], lockPeriod[stakingId], offset);

    // update the state variables
    totalStaked -= deposits[stakingId];
    delete deposits[stakingId];
    delete userInfo[_msgSender()];

    uint256 csi = _stakerIndexMap[_msgSender()];
    totalStakers--;
    stakers[csi] = stakers[totalStakers];
    _stakerIndexMap[stakers[csi]] = csi;
    delete stakers[totalStakers];
    delete _stakerIndexMap[_msgSender()];
  }

  /**
   * @notice
   *  reflect the total weighted score calculated from the external script(off-chain) to the contract.
   *  this function supposed to be called every week.
   *  only government can call this function
   * @param _totalWeightedScore total weighted score
   * @param weekNumber the week counter
   */
  function updatePool(uint256 _totalWeightedScore, uint256 weekNumber) external {
    if (_msgSender() != _government) revert NotGovernment(_msgSender());

    if (weekNumber <= lastRewardWeek) revert WeekNumberCannotBeLessThanOrEqualToLastRewardWeek(weekNumber, lastRewardWeek);
        
    for (uint256 i = lastRewardWeek + 1; i <= weekNumber; i++) {
      totalWeightedScore[i - 1] = _totalWeightedScore;
      if (i > 1 && rewardDrop[i - 1] == 0) {
        rewardDrop[i - 1] = rewardDrop[i - 2] - rewardDrop[i - 2] / 100;
      }
      
      uint256 _apr;
      if (totalStaked > 0) {
        _apr = rewardDrop[i - 1] * WEEKS_OF_ONE_YEAR * MAX_BPS / totalStaked;
      } else {
        _apr = MAX_APR;
      }
      
      if (_apr > MAX_APR) {
        rewardDrop[i - 1] = totalStaked * MAX_APR / WEEKS_OF_ONE_YEAR / MAX_BPS;

      } else if (_apr < MIN_APR) {
        rewardDrop[i - 1] = totalStaked * MIN_APR / WEEKS_OF_ONE_YEAR / MAX_BPS + 1;
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
    uint256 current = (block.timestamp - startBlockTime) / ONE_WEEK;
    uint256 _apr;
    if (totalStaked == 0 || current == 0) {
      _apr = MAX_APR;
    } else {
      _apr = rewardDrop[current - 1] * WEEKS_OF_ONE_YEAR * MAX_BPS / totalStaked;
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
      return _pendingReward(_user) - userInfo[_user].rewardDebt;
    }
  }

  function government() external view returns (address) {
    return _government;
  }

  //////////////////////////////
  ////    Admin functions   ////
  //////////////////////////////

  function addReward() external payable {

    if (_msgSender() != owner()) revert NotOwner(_msgSender());

    if (msg.value == 0) revert CannotAddZeroReward();

    uint256 amount = msg.value;

    treasury += amount;

    emit RewardAdded(amount, treasury);
  }

  function withdrawReward(uint256 amount) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (amount > treasury) {
        amount = treasury;
    }
    (bool success, ) = payable(_msgSender()).call{value: amount}("");
    if (!success) revert TransferFailed();

    treasury -= amount;

    emit RewardWithdrawn(amount, treasury);
  }

  function withdrawDeductedBalance() external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (deductedBalance == 0) revert DeductedBalanceIsZero();
    (bool success, ) = payable(_msgSender()).call{value: deductedBalance}("");
    if (!success) revert TransferFailed();
    emit DeductedBalanceWithdrawn(deductedBalance);
    delete deductedBalance;
  }

  function setLockTime(uint256 _lockTime) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_lockTime == 0) revert LockTimeCannotBeZero();
    emit LockTimeChanged(lockTime, _lockTime);
    lockTime = _lockTime;
  }

  function setReductionPercent(uint256 _reductionPercent) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_reductionPercent >= MAX_BPS) revert ReductionPercentTooHigh();
    emit ReductionPercentChanged(reductionPercent, _reductionPercent);
    reductionPercent = _reductionPercent;
  }

  function setRewardDrop(uint256 _rewardDrop) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (totalStaked == 0) revert NoStakedTokens();
    uint256 _apr = _rewardDrop * WEEKS_OF_ONE_YEAR * MAX_BPS / totalStaked;
    if (_apr < MIN_APR || _apr > MAX_APR) revert APRIsNotBetweenMinumumandMaximumAPR();
    uint256 current = (block.timestamp - startBlockTime) / ONE_WEEK;
    rewardDrop[current] = _rewardDrop;
    emit RewardDropUpdated(_rewardDrop, current);
  }

  function transferGovernance(address _newGov) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_newGov == address(0)) revert NewGovernmentAddressCannotBeZero();
    emit GovernanceTransferred(_government, _newGov);
    _government = _newGov;
  }

  function setActionLimit(uint256 _actionLimit) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_actionLimit == 0) revert NewValueCannotBeZero();
    emit ActionLimitChanged(actionLimit, _actionLimit);
    actionLimit = _actionLimit;
  }

  function setMaxActiveStake(uint256 _maxActiveStake) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_maxActiveStake == 0) revert NewValueCannotBeZero();
    emit MaxActiveStakeUpdated(maxActiveStake, _maxActiveStake);
    maxActiveStake = _maxActiveStake;
  }

  function setMaxWeeks(uint256 _maxWeeks) external {
    if (_msgSender() != multiSigWallet) revert NotMultiSig(_msgSender());
    if (_maxWeeks == 0) revert NewValueCannotBeZero();
    MaxWeeks = _maxWeeks;
  }

  /////////////////////////////////
  ////    Internal functions   ////
  /////////////////////////////////

  // get the total staked amount of user
  function _getTotalStaked(address user) internal view returns (uint256) {
    uint256 _totalStaked;
    uint256[] memory stakingIds = userInfo[user].stakingIds;
    // the length of `stakingIds` is limited to `maxActiveStake` to avoid too much gas consumption.
    for (uint i = 0; i < stakingIds.length; i++) {
      uint256 stakingId = stakingIds[i];
      _totalStaked += deposits[stakingId];
    }

    return _totalStaked;
  }

  function _pendingReward(address _user) internal view returns (uint256) {
    uint256 reward;
    uint256 firstStakingId = userInfo[_user].stakingIds[0];
    uint256 firstStakeWeek = (stakeTime[firstStakingId] - startBlockTime) / ONE_WEEK;
    uint256 current = (block.timestamp - startBlockTime) / ONE_WEEK;
    uint256 maxWeek = firstStakeWeek + MaxWeeks;

    for (uint i = firstStakeWeek; i <= current && i <= maxWeek; i++) {
        uint256 weightedScore = _getWeightedScore(_user, i);
        if (totalWeightedScore[i] != 0) {
            reward += rewardDrop[i] * weightedScore / totalWeightedScore[i];
        }
    }
    return reward;
  }


  function _getWeightedScore(address _user, uint256 weekNumber) internal view returns (uint256) {
    // calculate the basic score
    uint256 score;
    uint256[] memory stakingIds = userInfo[_user].stakingIds;
    // the length of `stakingIds` is limited to `maxActiveStake` to avoid too much gas consumption.
    for (uint i = 0; i < stakingIds.length; i++) {
      uint256 stakingId = stakingIds[i];
      uint256 _score = getScore(stakingId, weekNumber);
      score += _score;

    }

    // calculate the weighted score
    if (score == 0) return 0;

    uint256 weightedScore;
    for (uint i = 0; i < scoreLevels.length; i++) {
      if (score > scoreLevels[i]) {
        weightedScore = score * rewardMultiplier[scoreLevels[i]];
      } else {
        return weightedScore;
      }
    }

    return weightedScore;

  }

  function getScore(uint256 stakingId, uint256 weekNumber) internal view returns (uint256) {
    uint256 score;
    uint256 stakeWeek = (stakeTime[stakingId] - startBlockTime) / ONE_WEEK;
    if (stakeWeek > weekNumber) return 0;
    uint256 diff = weekNumber - stakeWeek > WEEKS_OF_ONE_YEAR ? WEEKS_OF_ONE_YEAR : weekNumber - stakeWeek;
    uint256 lockScore = deposits[stakingId] * uint256(lockPeriod[stakingId]) * 3 / 12;
    score = deposits[stakingId] * (diff + 1) / WEEKS_OF_ONE_YEAR + lockScore;
    if (score > deposits[stakingId]) {
      score = deposits[stakingId] / 1e18;
    } else {
      score = score / 1e18;
    }

    return score;
  }
}