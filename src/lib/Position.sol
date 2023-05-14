// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { min } from "./Math.sol";


struct Position {
    address owner; 
    uint256 recurringAmount;
    uint256 epochs;
    uint256 epoch0;
    uint256 withdrawn;
}

library PositionUtils {

    function create(
        address owner, 
        uint256 recurringAmount, 
        uint256 epochs, 
        uint256 epoch0
    ) internal pure returns (Position memory) {
        return Position(owner, recurringAmount, epochs, epoch0, 0);
    }

    function isActive(Position memory position, uint256 currentEpoch) internal pure returns (bool) {
        return position.epoch0 + position.epochs > currentEpoch && currentEpoch >= position.epoch0;
    }

    function isFilled(Position memory position, uint256 currentEpoch, uint256 swappedMake) internal pure returns (bool) {
        uint256 nonswappedUnlocked = unlocked(position, currentEpoch) - swappedMake;
        uint256 finalEpoch = position.epoch0 + position.epochs;
        return nonswappedUnlocked > 0 && currentEpoch > finalEpoch;
    }

    function unlocked(Position memory position, uint256 currentEpoch) internal pure returns (uint256) {
        if (currentEpoch < position.epoch0)
            return 0;
        uint256 activeEpochs = min(position.epochs, currentEpoch - position.epoch0 + 1);
        return activeEpochs * position.recurringAmount;
    }

    function locked(Position memory position, uint256 currentEpoch) internal pure returns (uint256) {
        if (currentEpoch < position.epoch0)
            return position.recurringAmount * position.epochs;
        uint256 activeEpochs = min(position.epochs, currentEpoch - position.epoch0);
        return (position.epochs - activeEpochs) * position.recurringAmount;
    }

}