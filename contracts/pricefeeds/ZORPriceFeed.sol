// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "./_PriceFeedBase.sol";

/// @title ZORPriceFeed
contract ZORPriceFeed is PriceFeedBase {
    /* State */

    address public zorToken;
    address public zorLPOtherToken;
    address public usdcToken;

    /* Constructor */

    function initialize(
        address _router,
        address _zorToken,
        address _zorLPOtherToken,
        address _usdcToken
    ) public initializer {
        PriceFeedBase.initialize(_router, 18);

        zorToken = _zorToken;
        zorLPOtherToken = _zorLPOtherToken;
        usdcToken = _usdcToken;
    }

    /* Functions */

    function _getExchRate() internal view override returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = zorToken;
        _path[1] = zorLPOtherToken;
        _path[2] = usdcToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(
            _amtIn,
            _path
        );
        return (_amts[_amts.length - 1] * (10**18) * (10**12)) / _amtIn;
    }
}
