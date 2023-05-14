// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


interface IDcaVault {

    event Deposit(address indexed owner, uint256 reccuringAmount, uint256 epochs);
    event Swap(address taker, uint256 makeAmount, uint256 takeAmount);
    event Withdraw(address indexed owner, uint256 amount);
    event ClosePosition(bytes32 indexed positionId, uint256 remainingAmount);
    event NewEpoch(uint256 indexed epoch);

    struct EpochInfo {
        uint256 takeInflow;
        uint256 makeOutflow;
        uint256 intialUnlockedMakeBalance;
    }

}