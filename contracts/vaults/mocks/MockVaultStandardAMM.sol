// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultStandardAMM.sol";

contract MockVaultFactoryStandardAMM is VaultFactoryStandardAMM {

}

contract MockVaultStandardAMM is VaultStandardAMM {
    function reversePath(address[] memory _path) public pure returns (address[] memory) {
        return _reversePath(_path);        
    }
}