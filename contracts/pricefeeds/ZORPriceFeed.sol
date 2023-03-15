// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Uniswap/IAMMRouter02.sol";

import "./_PriceFeedAggBase.sol";

/// @title ZORPriceFeed
contract ZORPriceFeed is PriceFeedAggBase {
    /* State */

    address public zorToken;
    address public zorLPOtherToken;
    address public busdToken;

    /* Constructor */

    function initialize(
        address _router,
        address _zorToken,
        address _zorLPOtherToken,
        address _busdToken
    ) public initializer {
        PriceFeedAggBase.initialize(_router, 18);

        zorToken = _zorToken;
        zorLPOtherToken = _zorLPOtherToken;
        busdToken = _busdToken;
    }

    /* Functions */

    function _getExchRate() internal view override returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = zorToken; // 18 decimals
        _path[1] = zorLPOtherToken;
        _path[2] = busdToken; // 18 decimals
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(
            _amtIn,
            _path
        );
        return (_amts[_amts.length - 1]) / _amtIn;
    }
}
