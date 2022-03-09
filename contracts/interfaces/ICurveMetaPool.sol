// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICurveMetaPool {
    function base_coins(uint256 i) external view returns(address);

    function coins(uint256 i) external view returns(address);

    function get_dy(int128 i, int128 j, uint256 _dx) external view returns(uint256);

    function exchange(int128 i, uint128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);

    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
}
