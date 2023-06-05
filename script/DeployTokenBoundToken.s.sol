// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/TokenBoundToken.sol";

contract DeployAccount is Script {
    function run() external {
        address payee = vm.envAddress("TESTNET_PAYEE");
        uint256 deployerPrivateKey = vm.envUint("TESTNET_DEPLOYER");
        vm.startBroadcast(deployerPrivateKey);

        new TokenBoundToken(
            "TestTokenBoundToken",
            "TBT",
            payee, // fee recipient
            false, // soulbound flag
            80000000000000000 // cost to mint
        );

        vm.stopBroadcast();
    }
}
