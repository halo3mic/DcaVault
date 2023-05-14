// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/lib/WoofiPriceFeed.sol";
import "../src/DcaVault.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address woofiOptimismOracle = 0x464959aD46e64046B891F562cFF202a465D522F3;
        address OptimisticUSDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        address OptimisticWETH = 0x4200000000000000000000000000000000000006;
        address oracle = address(new WoofiPriceFeed(woofiOptimismOracle, OptimisticUSDC));
        uint256 epochDuration = 5 minutes;

        address vault = address(new DcaVault(
            OptimisticUSDC,
            OptimisticWETH,
            epochDuration, 
            oracle
        ));
        
        console2.log("Vault deployed at address %s", vault);

        vm.stopBroadcast();
    }
}
