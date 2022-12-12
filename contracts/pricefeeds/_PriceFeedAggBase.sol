// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../interfaces/Uniswap/IAMMRouter02.sol";

abstract contract PriceFeedAggBase is AggregatorV3Interface, OwnableUpgradeable {
    /* State */

    address public router;
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 internal _rid;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    /* Constructor */

    function initialize(
        address _router,
        uint8 _decimals
    ) public initializer {
        router = _router;
        decimals = _decimals;
    }

    /* Functions */

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
        require(_roundId >= 0);
        return this.latestRoundData();
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
            int256(_getExchRate()),
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function _getExchRate() internal view virtual returns (uint256);
}
