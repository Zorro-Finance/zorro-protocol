// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "./_PriceFeedBase.sol";

/// @title BANANAPriceFeed
contract BANANAPriceFeed is PriceFeedBase {
    /* State */

    address public bananaToken;
    address public busdToken;

    /* Constructor */

    function initialize(
        address _router,
        address _bananaToken,
        address _busdToken
    ) public initializer {
        PriceFeedBase.initialize(_router, 18);

        bananaToken = _bananaToken;
        busdToken = _busdToken;
    }

    /* Functions */

    function _getExchRate() internal view override returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = bananaToken;
        _path[1] = busdToken;
        uint256 _amtIn = 1 ether;
        uint256[] memory _amts = IAMMRouter02(router).getAmountsOut(
            _amtIn,
            _path
        );
        return (_amts[_amts.length - 1] * (10**18) * (10**12)) / _amtIn;
    }
}
