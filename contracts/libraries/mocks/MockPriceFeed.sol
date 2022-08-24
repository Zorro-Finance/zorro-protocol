// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../PriceFeed.sol";

import "../../interfaces/IAMMRouter02.sol";

/// @title MockPriceFeed: Mock contract for testing the PriceFeed library
contract MockPriceFeed {
    using PriceFeed for AggregatorV3Interface;

    function getExchangeRate(address _priceFeed)
        public
        view
        returns (uint256)
    {
        return AggregatorV3Interface(_priceFeed).getExchangeRate();
    }
}

contract MockAggregatorV3 is AggregatorV3Interface {
    constructor() {
        decimals = 18;
        _answer = 1e18;
    }

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

contract MockPriceAggToken0 is MockAggregatorV3 {}
contract MockPriceAggToken1 is MockAggregatorV3 {}
contract MockPriceAggEarnToken is MockAggregatorV3 {}
contract MockPriceAggZOR is MockAggregatorV3 {}
contract MockPriceAggLPOtherToken is MockAggregatorV3 {}
contract MockPriceUSDC is MockAggregatorV3 {}
contract MockPriceBUSD is MockAggregatorV3 {}

/// @title MockPriceAggZORLP 
contract MockPriceAggZORLP is AggregatorV3Interface {
    using SafeMathUpgradeable for uint256;

    address public router;
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 internal _rid;
    int256 internal _answer;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    address public zorToken;
    address public zorLPOtherToken;
    address public usdcToken;

    constructor(address _router, address _zorToken, address _zorLPOtherToken, address _usdcToken) {
        router = _router;
        decimals = 18;
        _answer = 1e18;
        zorToken = _zorToken;
        zorLPOtherToken = _zorLPOtherToken;
        usdcToken = _usdcToken;
    }

    function setDecimals(uint8 _dec) public {
        decimals = _dec;
    }

    function setAnswer(int256 _ans) public {
        _answer = _ans;
    }

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
            int256(_getZORUSDExchRate()),
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
            int256(_getZORUSDExchRate()),
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function _getZORUSDExchRate() internal view returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = zorToken;
        _path[1] = zorLPOtherToken;
        _path[2] = usdcToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(_amtIn, _path);
        return _amts[_amts.length.sub(1)].mul(10**18).mul(10**12).div(_amtIn); 
    }
}

/// @title MockPriceAggSTG 
contract MockPriceAggSTG is AggregatorV3Interface {
    using SafeMathUpgradeable for uint256;

    address public router;
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 internal _rid;
    int256 internal _answer;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    address public stgToken;
    address public wavaxToken;
    address public usdcToken;

    constructor(address _router, address _stgToken, address _wavaxToken, address _usdcToken) {
        router = _router;
        decimals = 18;
        _answer = 1e18;
        stgToken = _stgToken;
        wavaxToken = _wavaxToken;
        usdcToken = _usdcToken;
    }

    function setDecimals(uint8 _dec) public {
        decimals = _dec;
    }

    function setAnswer(int256 _ans) public {
        _answer = _ans;
    }

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
            int256(_getSTGUSDExchRate()),
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
            int256(_getSTGUSDExchRate()),
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function _getSTGUSDExchRate() internal view returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = stgToken;
        _path[1] = wavaxToken;
        _path[2] = usdcToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(_amtIn, _path);
        return _amts[_amts.length.sub(1)].mul(10**18).mul(10**12).div(_amtIn); 
    }
}