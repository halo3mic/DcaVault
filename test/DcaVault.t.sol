// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solmate/tokens/ERC20.sol";

import "../src/DcaVault.sol";
import "../src/lib/PriceFeed.sol";
import { PositionUtils, Position } from "../src/lib/Position.sol";

contract DummyERC20 is ERC20 {

    constructor(string memory label, uint8 dec) ERC20(label, label, dec) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract Maker {

    string name; 

    constructor(string memory _name) {
        name = _name;
    }

    function deposit(address vault, uint amount, uint epochs) external returns (bytes32) {
        ERC20(DcaVault(vault).makeAsset()).approve(vault, type(uint).max);
        return DcaVault(vault).deposit(amount, epochs);
    }

    function withdraw(address vault, bytes32 positionId) external {
        DcaVault(vault).withdraw(positionId);
    }

    function closePosition(address vault, bytes32 positionId) external {
        DcaVault(vault).closePosition(positionId);
    }

}

contract Taker {

    string name;

    constructor(string memory _name) {
        name = _name;
    }

    function swap(address vault, uint256 amount) external {
        ERC20(DcaVault(vault).takeAsset()).transfer(vault, amount);
        DcaVault(vault).swapPush();
    }

}

contract DummyGmxPriceFeed is PriceFeed {

    uint256 price = 1795854000000000000000000000000000;
    bool isActive = true;

    function setIsActive(bool _isActive) external {
        isActive = _isActive;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function active(address, address) override external view returns (bool) {
        return isActive;
    }

    function precision() override external view returns (uint256) {
        return 1e30;
    }

    function getLatestPrice(address quote, address base) override external view returns (uint256) {
        return price;
    }

}

interface ICheats {
    function warp(uint256) external;
}

contract DcaVaultTest is Test {
    using PositionUtils for Position;

    address defaultPriceFeed = address(new DummyGmxPriceFeed());
    ICheats cheats = ICheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address dUSDC = address(new DummyERC20("dUSDC", 6));
    address dETH = address(new DummyERC20("dETH", 18));

    function testDeposit() public {
        // Init
        address makeAsset = dUSDC;
        address takeAsset = dETH;
        uint epochDuration = 1 days;
        DcaVault vault = new DcaVault(
            makeAsset,
            takeAsset,
            epochDuration,
            defaultPriceFeed
        );

        DummyERC20(makeAsset).mint(address(this), 100 ether);
        DummyERC20(takeAsset).mint(address(this), 100 ether);
        ERC20(makeAsset).approve(address(vault), type(uint).max);
        
        // Deposit
        uint256 amount = 11 ether;
        uint256 epochs = 3;

        uint makeBal0 = ERC20(makeAsset).balanceOf(address(this)); 
        bytes32 positionId = vault.deposit(amount, epochs);
        uint makeBal1 = ERC20(makeAsset).balanceOf(address(this)); 

        // Check
        Position memory pos = vault.getPositionForId(positionId);
        assertEq(makeBal0-makeBal1, pos.recurringAmount*pos.epochs, "only take multiple of the epoch duration");
        assertEq(pos.owner, address(this), "position owner is correct");
        assertEq(pos.epochs, epochs, "epochs is correct");
        assertEq(pos.epoch0, vault.currentEpoch()+1, "epoch0 is the following epoch");

        // User can immediatly close the position
        vault.closePosition(positionId);
        uint makeBal2 = ERC20(makeAsset).balanceOf(address(this));
        assertEq(makeBal0, makeBal2, "user shouldn't lose money if he cancels immediatly");

        // after closing counters are affected 
        assertEq(vault.recurringPending(), 0, "recurringPending is reset after closing");
        assertEq(vault.getPositionForId(positionId).owner, address(0), "position is empty after closing");
    }
    
    function testSwap() public {
        // Init
        address makeAsset = dUSDC;
        address takeAsset = dETH;
        uint epochDuration = 1 days;
        DcaVault vault = new DcaVault(
            makeAsset,
            takeAsset,
            epochDuration,
            defaultPriceFeed
        );

        DummyERC20(makeAsset).mint(address(this), 100 ether);
        DummyERC20(takeAsset).mint(address(this), 100 ether);
        ERC20(makeAsset).approve(address(vault), type(uint).max);
        
        // Deposit
        uint256 depositAmount = 100_000e6;
        uint256 epochs = 3;
        bytes32 positionId = vault.deposit(depositAmount, epochs);

        uint256 depositedAmount = vault.getPositionForId(positionId).recurringAmount*epochs;

        // Warp to the next epoch
        cheats.warp(epochDuration+1);

        // Query & Swap
        uint256 swapAmount = 2 ether;
        uint256 expectedAmountOut = 2*1795854000;
        uint256 queryAmountOut = vault.query(swapAmount);
        assertEq(queryAmountOut, expectedAmountOut, "queryAmountOut must be 1795854000");

        ERC20(takeAsset).transfer(address(vault), swapAmount);
        uint256 makeAmountBal0 = ERC20(makeAsset).balanceOf(address(this));
        vault.swapPush();
        uint256 makeAmountBal1 = ERC20(makeAsset).balanceOf(address(this));
        uint256 swapAmountOut = makeAmountBal1-makeAmountBal0;

        assertEq(swapAmountOut, queryAmountOut, "queryAmountOut must match swapAmountOut");

        // Check
        Position memory pos = vault.getPositionForId(positionId);
        assertEq(ERC20(takeAsset).balanceOf(address(vault)), swapAmount, "take balance is increased");
        assertEq(vault.makeSwappableBal(), pos.recurringAmount-swapAmountOut, "makeSwappableBal is decreased");
        assertEq(vault.getInfoForEpoch(vault.currentEpoch()).takeInflow, swapAmount);

        // User can close the position
        uint makeBal0 = ERC20(makeAsset).balanceOf(address(this));
        uint takeBal0 = ERC20(takeAsset).balanceOf(address(this));
        vault.closePosition(positionId);
        uint makeBal1 = ERC20(makeAsset).balanceOf(address(this));
        uint takeBal1 = ERC20(takeAsset).balanceOf(address(this));

        uint makeDiff = makeBal1-makeBal0;
        uint takeDiff = takeBal1-takeBal0;
        assertEq(makeDiff, depositedAmount-swapAmountOut, "makeDiff eq whatever wasn't traded");
        assertEq(takeDiff, swapAmount, "takeDiff eq whatever was traded");

        assertEq(vault.recurringPending(), 0, "recurringPending is reset after closing");
        assertEq(vault.getPositionForId(positionId).owner, address(0), "position is empty after closing");
    }

    function testScenarioA() public {
        // 🪄 Init
        address makeAsset = dUSDC;
        address takeAsset = dETH;
        uint epochDuration = 1 days;
        DummyGmxPriceFeed priceFeed = new DummyGmxPriceFeed();
        priceFeed.setPrice(25e30);
        DcaVault vault = new DcaVault(
            makeAsset,
            takeAsset,
            epochDuration,
            address(priceFeed)
        );

        // 🙋‍♂️ Define users
        Maker alice = new Maker("Alice");
        Maker bob = new Maker("Bob");
        Maker tom = new Maker("Tom");
        Taker taker = new Taker("Taker");

        // 🖨️ Mint tokens to users
        DummyERC20(makeAsset).mint(address(alice), 100e6);
        DummyERC20(makeAsset).mint(address(bob), 100e6);
        DummyERC20(makeAsset).mint(address(tom), 100e6);
        DummyERC20(takeAsset).mint(address(taker), 14 ether);
        
        // 💰 Alice & Bob both deposit 100 dUSDC 2 epochs
        uint256 depositAmount = 100e6;
        bytes32 alicePositionId = alice.deposit(address(vault), depositAmount, 2);
        bytes32 bobPositionId = bob.deposit(address(vault), depositAmount, 2);

        // ⏱️ Warp to the next epoch
        cheats.warp(block.timestamp + epochDuration + 1);

        // 💱 Taker swaps
        taker.swap(address(vault), 4 ether);

        // 💰 Tom deposits 100 dUSDC 1 epoch
        bytes32 tomPositionId = tom.deposit(address(vault), depositAmount, 1);

        // ⏱️ Warp to the next epoch
        cheats.warp(block.timestamp + epochDuration+1);

        // Change the price
        priceFeed.setPrice(20e30);

        // 💱 Taker swaps 10 ether
        taker.swap(address(vault), 10 ether);

        // 🚪 All makers withdraw (and close their positions)
        alice.withdraw(address(vault), alicePositionId);
        bob.withdraw(address(vault), bobPositionId);
        tom.withdraw(address(vault), tomPositionId);

        // ✅ Check balances are distributed correctly
        uint256 takeBalAlice = ERC20(takeAsset).balanceOf(address(alice));
        uint256 takeBalBob = ERC20(takeAsset).balanceOf(address(bob));
        uint256 takeBalTom = ERC20(takeAsset).balanceOf(address(tom));
        assertEq(takeBalAlice, 4.5 ether, "Alice should have 4.5 dETH");
        assertEq(takeBalBob, 4.5 ether, "Bob should have 4.5 dETH");
        assertEq(takeBalTom, 5 ether, "Tom should have 5 dETH");

    }

    function testScenarioB() public {
        // 🪄 Init
        address makeAsset = dUSDC;
        address takeAsset = dETH;
        uint epochDuration = 1 days;
        DummyGmxPriceFeed priceFeed = new DummyGmxPriceFeed();
        DcaVault vault = new DcaVault(
            makeAsset,
            takeAsset,
            epochDuration,
            address(priceFeed)
        );

        // 🙋‍♂️ Define users
        Maker alice = new Maker("Alice");
        Maker bob = new Maker("Bob");
        Maker tom = new Maker("Tom");
        Taker taker = new Taker("Taker");

        // 🖨️ Mint tokens to users
        DummyERC20(makeAsset).mint(address(alice), 90e6);
        DummyERC20(makeAsset).mint(address(bob), 90e6);
        DummyERC20(makeAsset).mint(address(tom), 90e6);
        DummyERC20(takeAsset).mint(address(taker), 15 ether);
        
        // 💰 Alice & Bob both deposit 90 dUSDC for 2 and 1 epochs, respectively
        uint256 depositAmount = 90e6;
        bytes32 bobPositionId = bob.deposit(address(vault), depositAmount, 1);
        bytes32 alicePositionId = alice.deposit(address(vault), depositAmount, 2);

        // ⏱️ Warp to the next epoch
        cheats.warp(block.timestamp + epochDuration + 1);
        vault.updateEpoch();

        // Check state
        assertEq(vault.makeSwappableBal(), 135e6, "Total swappable is 135 dUSDC");
        assertEq(vault.getPositionForId(bobPositionId).unlocked(vault.currentEpoch()), 90e6, "Bob's unlocked is 90 dUSDC");
        assertEq(vault.getPositionForId(alicePositionId).unlocked(vault.currentEpoch()), 45e6, "Alice's unlocked is 45 dUSDC");

        // 📈 Price changes
        priceFeed.setPrice(30e30);

        // 💱 Taker swaps
        taker.swap(address(vault), 3 ether);

        // Check state
        (uint bobMakeSwapped, uint bobTakeSwapped) = vault.getSwappedAmounts(bobPositionId);
        (uint aliceMakeSwapped, uint aliceTakeSwapped) = vault.getSwappedAmounts(alicePositionId);
        assertEq(bobMakeSwapped, 60e6, "Bob should have swapped 60 dUSDC");
        assertEq(bobTakeSwapped, 2 ether, "Bob should get 2 dETH");
        assertEq(aliceMakeSwapped, 30e6, "Alice should have swapped 30 dUSDC");
        assertEq(aliceTakeSwapped, 1 ether, "Alice should get 1 dETH");
        assertEq(vault.makeSwappableBal(), 45e6, "Total swappable should be 45 dUSDC");

        // 💰 Tom deposits 90 dUSDC for 1 epoch
        bytes32 tomPositionId = tom.deposit(address(vault), depositAmount, 1);

        // ⏱️ Warp to the next epoch
        cheats.warp(block.timestamp + epochDuration+1);
        vault.updateEpoch();

        // Check state
        assertEq(vault.makeSwappableBal(), 180e6, "Total swappable is 180 dUSDC");
        assertEq(vault.getPositionForId(tomPositionId).unlocked(vault.currentEpoch()), 90e6, "Tom's unlocked is 100 dUSDC");
        assertEq(vault.getPositionForId(alicePositionId).unlocked(vault.currentEpoch()), 90e6, "Alice's unlocked is 100 dUSDC");

        // 📈 Price changes
        priceFeed.setPrice(15e30);

        // 💱 Taker swaps
        taker.swap(address(vault), 12 ether);
        
        // Check state
        (bobMakeSwapped, bobTakeSwapped) = vault.getSwappedAmounts(bobPositionId);
        (aliceMakeSwapped, aliceTakeSwapped) = vault.getSwappedAmounts(alicePositionId);
        (uint tomMakeSwapped, uint tomTakeSwapped) = vault.getSwappedAmounts(tomPositionId);
        assertEq(bobMakeSwapped, 90e6, "Bob should have swapped 90 dUSDC"); // NOTE: 1 dUSDC dust
        assertEq(bobTakeSwapped, 4 ether, "Bob should get 4 dETH");
        assertEq(aliceMakeSwapped, 90e6, "Alice should have swapped 100 dUSDC"); // NOTE: 1 dUSDC dust
        assertEq(aliceTakeSwapped, 5 ether, "Alice should get 5 dETH");
        assertEq(tomMakeSwapped, 90e6, "Tom should have swapped 100 dUSDC");
        assertEq(tomTakeSwapped, 6 ether, "Tom should get 6 dETH");
        assertEq(vault.makeSwappableBal(), 0, "Total swappable should be 0 dUSDC");

        // 🚪 All makers withdraw (and close their positions)
        alice.withdraw(address(vault), alicePositionId);
        bob.withdraw(address(vault), bobPositionId);
        tom.withdraw(address(vault), tomPositionId);

        // ✅ Check balances are distributed correctly
        uint256 takeBalAlice = ERC20(takeAsset).balanceOf(address(alice));
        uint256 takeBalBob = ERC20(takeAsset).balanceOf(address(bob));
        uint256 takeBalTom = ERC20(takeAsset).balanceOf(address(tom));
        assertEq(takeBalTom, 6 ether, "Tom should have 6 dETH");
        assertEq(takeBalBob, 4 ether, "Bob should have 4 dETH");
        assertEq(takeBalAlice, 5 ether, "Alice should have 5 dETH");
    }

}
