// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../PriceFeed.sol";

/// @title MockPriceFeed: Mock contract for testing the PriceFeed library
contract MockPriceFeed {
    using PriceFeed for AggregatorV3Interface;

    function getExchangeRate(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint256)
    {
        return _priceFeed.getExchangeRate();
    }
}

contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 internal _rid;
    int256 internal _answer;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    function setDecimals(uint8 _dec) public {
        decimals = _dec;
    }

    function setAnswer(int256 _ans) public {
        _answer = _ans;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            _answer,
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _rid,
            _answer,
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }
}
