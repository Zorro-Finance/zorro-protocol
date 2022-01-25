// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.12 <0.9.0;

interface IAcryptosFarm {
    function deposit(address _lpToken, uint256 _amount) external;

    function withdraw(address _lpToken, uint256 _amount) external;
}
