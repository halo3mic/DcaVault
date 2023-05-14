// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


interface IERC20 {

    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns(bool);
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external returns (bool);
}