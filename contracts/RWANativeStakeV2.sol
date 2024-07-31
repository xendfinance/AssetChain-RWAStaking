// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RWANativeStake.sol";

contract RWANativeStakeV2 is RWANativeStake {
    function version() external pure returns (string memory) {
        return "v2";
    }
}