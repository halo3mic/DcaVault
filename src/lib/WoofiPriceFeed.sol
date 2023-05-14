// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./PriceFeed.sol";


interface IWoofiOracle {
    function price(address base) external view returns (uint256 price, bool feasible);
    function isWoFeasible(address base) external view returns (bool);
}

contract WoofiPriceFeed is PriceFeed {

    address immutable public oracle;
    address immutable public quote;

    constructor(address _oracle, address _quote) {
        oracle = _oracle;
        quote = _quote;
    }

    function active(address base, address) override external view returns (bool) {
        return IWoofiOracle(oracle).isWoFeasible(base);
    }

    function precision() override external pure returns (uint256) {
        return 1e8;
    }

    function getLatestPrice(address base, address _quote) override external view returns (uint256) {
        require(quote == _quote, "WoofiPriceFeed: quote mismatch");
        (uint256 price, bool feasible) = IWoofiOracle(oracle).price(base);
        require(feasible, "WoofiPriceFeed: oracle price is not feasible");
        return price;
    }

}