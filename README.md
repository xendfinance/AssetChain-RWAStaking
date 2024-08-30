# RWA Staking Smart Contracts
<sub> RWA is the native cryptocurrency for Asset Chain, similar to ETH on Ethereum.</sub>

## Table of content
- [Description](https://github.com/xendfinance/AssetChain-RWAStaking#description)
- [Parameters To Consider](https://github.com/xendfinance/AssetChain-RWAStaking#parameters-to-consider)
- [Developer Considerations](https://github.com/xendfinance/AssetChain-RWAStaking#getting-started)
- [Getting Started](https://github.com/xendfinance/AssetChain-RWAStaking#getting-started)
- [Contributing](https://github.com/xendfinance/AssetChain-RWAStaking#contributing)
- [License](https://github.com/xendfinance/AssetChain-RWAStaking#license)
- [Support](https://github.com/xendfinance/AssetChain-RWAStaking#support)

## Description
This project implements the RWA staking model for Asset Chain. The model allows users to stake RWA and earn a dynamic APR based on the total amount of RWA in the staking pool. 

There are two types of staking available:
1. **Fixed Staking**: Users can lock up RWA for a set period.
2. **Flexible Staking**: Users can stake and unstake RWA without a lock-up period.


### Parameters To Consider
1. **LockTime**:The minimum cool-down period after staking before unstaking or forced unstaking can occur. . **The default value is ONE WEEK**
2. **Reduction Percent**: The maximum percentage by which the total staked RWA will be slashed, proportional to the selected lock period. **The default value is 30%** *Example: If you select a 3-month lock and force unlock after 1 month, the slash will be ((3-1)/3) * (30%) * Total staked RWA*
3. **Action Limit**: This is the cool down period period between consecutive flexible staking operations. **Default value is 24 hours**
4. **Max Active Stake**: This is the maximum number of active staking operations a user can perform on flexible staking.  **Default value is 10**


### Developer Considerations
1. The Open Zeppelin Version that is compatible with solidity 0.6.12 which is openzeppelin 3.4 
2. You can upgrade the entire project to use higher versions of openzeppelin if you wish to but it means you might have to make code changes since the project uses SafeMath and this is no long available in very new Open Zeppelin libraries
3. If you have already installed the current open zeppelin version, you can simply run *npm install @openzeppelin/contracts@3.4* to downgrade and give you the supported version. 
4. Remember to change solidity compiler version in your config file to 0.6.12

## Getting Started
To get started, follow the steps below:

1. Clone this repo
  ``` bash
  git clone https://github.com/xendfinance/AssetChain-RWAStaking.git
  ```
2. cd into the project
3. Install the project's dependencies
  
  ``` bash
  yarn install
  npm install
  ```
4. Compile your contracts
   
  ``` bash
  npx hardhat compile
  ```
5. Start development

## Contributing

See [CONTRIBUTING.md](https://github.com/xendfinance/nodesale/CONTRIBUTING.md) for contribution and pull request protocol. We expect contributors to follow our guide when submitting code or comments.

## License

[![License: GPL v3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](LICENSE) file for details.

## Contact

For questions or suggestions, just say Hi on [Telegram](https://t.me/xendfinancedevs).<br/>
We're always glad to help.






