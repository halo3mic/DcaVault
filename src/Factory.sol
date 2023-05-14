// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "./DcaVault.sol";


// contract DcaVaultFactory {

//     mapping(address => mapping(address => mapping(uint256 => address))) paramsToVault;
//     mapping(address => mapping(address => uint256[])) makeToTakeToEpochDurations; 


//     function create(address makeAsset, address takeAsset, uint256 epochDuration) public returns (address) {
//         require(paramsToVault[makeAsset][takeAsset][epochDuration] == address(0), "DcaVaultFactory: vault already exists");

//         bytes memory bytecode = type(DcaVault).creationCode;
//         bytes32 salt = keccak256(abi.encodePacked(makeAsset, takeAsset, epochDuration));
//         address addr;
//         assembly {
//             addr := create2(0, add(bytecode, 32), mload(bytecode), salt)
//         }
//         require(addr != address(0), "DcaVaultFactory: failed to create vault");

//         paramsToVault[makeAsset][takeAsset][epochDuration] = addr;
//         makeToTakeToEpochDurations[makeAsset][takeAsset].push(epochDuration);

//         return addr;
//     }

// }