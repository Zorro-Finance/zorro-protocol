// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library CustomMath {
    /**
     * @dev Returns the square root of the provided value (approximate)
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        else if (x <= 3) return 1;
        uint z = (x + 1) / 2;
        y = x;
        while (z < y)
        {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}