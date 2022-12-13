// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/Benqi/IUnitroller.sol";

import "./_VaultActionsLending.sol";

contract VaultActionsBenqiLending is VaultActionsLending {
    /* Utilities */

    /// @notice Gets loan collateral factor from lending protocol
    /// @return collFactor The collateral factor %. (1e18 = 100%)
    /// @param _comptrollerAddress Address of the ApeLending Unitroller proxy
    /// @param _poolAddress Address of the lending pool
    function collateralFactor(address _comptrollerAddress, address _poolAddress)
        public
        view
        override
        returns (uint256 collFactor)
    {
        (, uint256 _collateralFactor, ) = IUnitrollerBenqi(_comptrollerAddress)
            .markets(_poolAddress);
        return _collateralFactor;
    }
}
