// SPDX-License-Identifier: MIT

pragma solidity >0.5.16;

interface IRainMaker {
    /*** Comp claiming ***/
    function claimComp(address holder) external;
}