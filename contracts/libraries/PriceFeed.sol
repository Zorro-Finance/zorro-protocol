// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";


library PriceFeed {
    /* Libraries */
    using SafeMath for uint256;

    /* Functions */
    
    /// @notice Calculates exchange rate vs USD for a given priceFeed
    /// @dev Assumes price feed is in USD. If not, either multiply obtained exchange rate with another, or override this func.
    /// @param _priceFeed The Chainlink price feed
    /// @return uint256 Exchange rate vs USD, multiplied by 1e12
    function getExchangeRate(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint256)
    {
        // Use price feed to determine exchange rates
        uint8 _decimals = _priceFeed.decimals();
        (, int256 _price, , , ) = _priceFeed.latestRoundData();

        // Safeguard on signed integers
        require(_price >= 0, "neg prices not allowed");

        // Get the price of the token times 1e12, accounting for decimals
        return uint256(_price).mul(1e12).div(10**_decimals);
    }
}