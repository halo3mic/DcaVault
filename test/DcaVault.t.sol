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

contract DummyGmxPriceFeed is PriceFeed {

    bool isActive = true;

    function setIsActive(bool _isActive) external {
        isActive = _isActive;
    }

    function active() override external view returns (bool) {
        return isActive;
    }

    function precision() override external view returns (uint256) {
        return 1e30;
    }

    function getLatestPrice(address quote, address base) override external view returns (uint256) {
        return 1795854000000000000000000000000000;
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

        // todo: don't allow trading when the price feed is not active
        // todo: make sure taker can't trade more than it is in the pool

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
        assertEq(vault.makeUnlockedBalance(), pos.recurringAmount-swapAmountOut, "makeUnlockedBalance is decreased");
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

    // test gas cost withdrawing from many epochs

    // test case1 (see the ipad sketch)

}
