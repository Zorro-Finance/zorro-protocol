// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Uniswap/IAMMRouter02.sol";

import "./_PriceFeedAggBase.sol";

/// @title STGPriceFeed
contract STGPriceFeed is PriceFeedAggBase {
    /* State */

    address public stgToken;
    address public wavaxToken;
    address public usdcToken;

    /* Constructor */

    function initialize(
        address _router,
        address _stgToken,
        address _wavaxToken,
        address _usdcToken
    ) public initializer {
        PriceFeedAggBase.initialize(_router, 18);

        stgToken = _stgToken;
        wavaxToken = _wavaxToken;
        usdcToken = _usdcToken;
    }

    /* Functions */

    function _getExchRate() internal view override returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = stgToken;
        _path[1] = wavaxToken;
        _path[2] = usdcToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(
            _amtIn,
            _path
        );
        return (_amts[_amts.length - 1] * (10**18) * (10**12)) / _amtIn;
    }
}
