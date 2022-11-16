// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../interfaces/IAMMRouter02.sol";

/// @title BANANAPriceFeed
contract BANANAPriceFeed is AggregatorV3Interface {
    using SafeMathUpgradeable for uint256;

    address public router;
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 internal _rid;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _answeredInRound;

    address public bananaToken;
    address public busdToken;

    constructor(address _router, address _bananaToken, address _busdToken) {
        router = _router;
        decimals = 18;
        bananaToken = _bananaToken;
        busdToken = _busdToken;
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
        require(_roundId>=0);
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
            int256(_getZORUSDExchRate()),
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function _getZORUSDExchRate() internal view returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = bananaToken;
        _path[1] = busdToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(_amtIn, _path);
        return _amts[_amts.length.sub(1)].mul(10**18).mul(10**12).div(_amtIn); 
    }
}