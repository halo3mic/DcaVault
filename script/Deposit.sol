// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interface/IERC20.sol";
import "../src/lib/WoofiPriceFeed.sol";
import "../src/DcaVault.sol";

contract Deposit is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ARBITRUM_PK_DEPLOYER");
        uint depositAmount = 100e6;
        uint epochs = 10;
        DcaVault vault = DcaVault(vm.envAddress("VAULT"));
        vm.startBroadcast(deployerPrivateKey);
        IERC20(vault.makeAsset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, epochs);

        vm.stopBroadcast();
    }
}
