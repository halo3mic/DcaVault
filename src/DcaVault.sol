// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import { PositionUtils, Position } from "./lib/Position.sol";
import { min } from "./lib/Math.sol";
import "./lib/PriceFeed.sol";
import "./interface/IDcaVault.sol";
import "./interface/IERC20.sol";


contract DcaVault is IDcaVault {
    using PositionUtils for Position;

    uint256 public immutable INIT_TIME = block.timestamp;
    uint256 public immutable epochDuration;
    address public immutable makeAsset;
    address public immutable takeAsset;
    address public immutable priceFeed;
    uint256 public immutable makeAssetDenominator;
    uint256 public immutable takeAssetDenominator;

    mapping(address => uint256) public userToPositions;
    mapping(uint256 => uint256) public epochToReccuringEnding; // How much will stop recurring from that epoch on
    mapping(bytes32 => Position) public idToPosition;
    mapping(uint256 => EpochInfo) public epochToInfo;
    uint256 public recurringPending;
    uint256 public currentEpoch;
    uint256 public makeUnlockedBalance;
    uint256 public reccuringAmount; 
    uint256 public takeBalance;

    constructor(
        address _makeAsset, 
        address _takeAsset, 
        uint256 _epochDuration, 
        address _priceFeed
    ) {
        epochDuration = _epochDuration;
        makeAsset = _makeAsset;
        takeAsset = _takeAsset;
        priceFeed = _priceFeed;
        makeAssetDenominator = 10**IERC20(_makeAsset).decimals();
        takeAssetDenominator = 10**IERC20(_takeAsset).decimals();
    }

    function deposit(uint256 amount, uint256 epochs) external returns (bytes32 positionId) {
        uint256 _reccuringAmount = amount / epochs;
        IERC20(makeAsset).transferFrom(msg.sender, address(this), _reccuringAmount*epochs); // don't transfer reminder
        recurringPending += _reccuringAmount;
        uint256 epoch0 = currentEpoch + 1; // first reinvest for the new deposit is only in the next epoch
        epochToReccuringEnding[epoch0 + epochs] += _reccuringAmount;

        positionId = makePositionId(msg.sender);
        idToPosition[positionId] = Position(msg.sender, _reccuringAmount, epochs, epoch0, 0);

        emit Deposit(msg.sender, _reccuringAmount, epochs);

        updateEpoch();
    }

    function withdraw(bytes32 positionId) external {
        updateEpoch();
        Position memory position = idToPosition[positionId];
        require(position.owner == msg.sender, "Not owner");
        uint swappedMake = _withdraw(position);

        if (position.isFilled(currentEpoch, swappedMake))
            _closePosition(positionId, 0);
    }

    function closePosition(bytes32 positionId) external {
        updateEpoch();
        Position memory position = idToPosition[positionId];
        require(position.owner == msg.sender, "Not owner");

        uint256 totalDeposit = position.recurringAmount * position.epochs;
        uint256 swappedMake = _withdraw(position);
        uint256 unspentMake = totalDeposit - swappedMake;

        if (unspentMake > 0)
            IERC20(makeAsset).transfer(msg.sender, unspentMake);

        // Rm from global counting
        uint256 unlockedMake = position.unlocked(currentEpoch) - swappedMake;
        makeUnlockedBalance -= unlockedMake;
        reccuringAmount -= unlockedMake;
        if (position.epoch0 == currentEpoch + 1)
            recurringPending -= position.recurringAmount;

        _closePosition(positionId, unspentMake);
    }

    function swapPull(uint256 amount) external {
        IERC20(takeAsset).transferFrom(msg.sender, address(this), amount);
        _swap(amount);
    }

    function swapPush() external {
        uint256 transferredIn = IERC20(takeAsset).balanceOf(address(this)) - takeBalance;
        _swap(transferredIn);
    }

    function updateEpoch() public {
        uint256 _epochNow = epochNow();
        uint256 epochDiff = _epochNow - currentEpoch;
        if (epochDiff == 0)
            return;

        // reccuring investments ending in the following epoch
        uint256 reccuringEnding; 
        // it is possible no one presses the button for a long time, so we need to update the state for all the epochs
        for (uint256 e = currentEpoch+1; e <= _epochNow; ++e) {
            reccuringEnding += epochToReccuringEnding[e];
            delete epochToReccuringEnding[e];
        } 
        reccuringAmount += recurringPending - reccuringEnding;
        recurringPending = 0;
        makeUnlockedBalance += reccuringAmount;
        currentEpoch = _epochNow;
        epochToInfo[_epochNow].intialUnlockedMakeBalance = makeUnlockedBalance;

        emit NewEpoch(_epochNow);
    }

    function query(uint256 takeAmount) public view returns (uint256) {
        uint256 makeAvailable = makeUnlockedBalance;
        if (epochNow() > currentEpoch) {
            uint256 reccuringEnding; 
            for (uint256 e = currentEpoch+1; e <= epochNow(); ++e) {
                reccuringEnding += epochToReccuringEnding[e];
            }
            makeAvailable += recurringPending - reccuringEnding;
        }
        uint256 makeAmount = _getMakeForTake(takeAmount);
        return min(makeAmount, makeAvailable);
    }

    function getPositionForId(bytes32 positionId) external view returns (Position memory) {
        return idToPosition[positionId];
    }

    function getInfoForEpoch(uint256 epoch) external view returns (EpochInfo memory) {
        return epochToInfo[epoch];
    }

    function getOraclePrice() public view returns (uint256) {
        // todo: figure out price precision
        return PriceFeed(priceFeed).getLatestPrice(makeAsset, takeAsset);
    }

    function getSwappedAmounts(bytes32 positionId) external view returns (uint256, uint256) {
        return _getSwappedAmounts(idToPosition[positionId]);
    }
    
    function epochNow() public view returns (uint256) {
        return (block.timestamp-INIT_TIME) / epochDuration;
    }

    function _swap(uint256 takeAmount) internal { // todo: use quote and base to avoid confusion
        require(PriceFeed(priceFeed).active(takeAsset, makeAsset), "Oracle not active");
        updateEpoch();
        uint256 makeAmount = _getMakeForTake(takeAmount);
        require(makeAmount <= makeUnlockedBalance, "Insufficient unlocked funds");

        makeUnlockedBalance -= makeAmount;
        takeBalance += takeAmount;
        epochToInfo[currentEpoch].takeInflow += takeAmount;
        epochToInfo[currentEpoch].makeOutflow += makeAmount;

        IERC20(makeAsset).transfer(msg.sender, makeAmount);
        emit Swap(msg.sender, makeAmount, takeAmount);
    }

    function _getMakeForTake(uint256 takeAmount) internal view returns (uint256) {
        return takeAmount
            * getOraclePrice()
            * makeAssetDenominator
            / takeAssetDenominator
            / PriceFeed(priceFeed).precision();
    }

    function _withdraw(Position memory position) internal returns (uint256) {
        (uint256 swappedMake, uint256 swappedTake) = _getSwappedAmounts(position);
        uint256 amountToWithdraw = swappedTake - position.withdrawn;
        takeBalance -= amountToWithdraw;
        if (amountToWithdraw > 0)
            IERC20(takeAsset).transfer(msg.sender, amountToWithdraw);
        emit Withdraw(msg.sender, amountToWithdraw);

        return swappedMake;
    }

    function _getSwappedAmounts(
        Position memory position
    ) internal view returns (uint256 swappedMake, uint256 swappedTake) {
        for (uint256 e = position.epoch0; e <= currentEpoch; ++e) {
            if (position.isFilled(e, swappedMake))
                break;

            EpochInfo memory epochInfo = epochToInfo[e];
            if (epochInfo.takeInflow == 0)
                continue;
            
            uint256 nonswappedUnlocked = position.unlocked(e) - swappedMake;
            uint256 epochSwappedTake = epochInfo.takeInflow * nonswappedUnlocked / epochInfo.intialUnlockedMakeBalance; // how much was swapped within epoch e in take asset for position
            uint256 epochSwappedMakeFull = e == currentEpoch
                ? epochInfo.intialUnlockedMakeBalance - makeUnlockedBalance
                : epochInfo.makeOutflow;
            uint256 epochSwappedMake = epochSwappedMakeFull * nonswappedUnlocked / epochInfo.intialUnlockedMakeBalance; // how much was swapped within epoch e in make asset for position
            swappedTake += epochSwappedTake;
            swappedMake += epochSwappedMake;
        }
    }

    function _closePosition(bytes32 positionId, uint256 unspentMake) internal {
        delete idToPosition[positionId];
        emit ClosePosition(positionId, unspentMake);
    }

    function makePositionId(address owner) internal returns (bytes32 id) {
        id = keccak256(abi.encodePacked(owner, userToPositions[owner]));
        userToPositions[owner] += 1;
    }

}
