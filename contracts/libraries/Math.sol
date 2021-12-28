// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.12 <0.9.0;

library Math {
    function sqrt(uint256 x) public pure returns (uint256 y) {
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