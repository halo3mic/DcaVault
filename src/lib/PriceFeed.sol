// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


abstract contract PriceFeed {

    function active() virtual external view returns (bool); // is oracle price stale?
    function precision() virtual external view returns (uint256);
    function getLatestPrice(address base, address quote) virtual external view returns (uint256);

}