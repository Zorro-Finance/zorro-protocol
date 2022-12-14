// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/Zorro/Controllers/IZorroController.sol";

contract ZorroControllerVaultMgmt is IZorroControllerVaultMgmt, ZorroControllerBase {
    /* Pool management */

    /// @notice Adds a new pool. Can only be called by the owner.
    /// @dev DO NOT add the same Want token more than once. Rewards will be messed up if you do. (Only if Want tokens are stored here.)
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _want The address of the want token
    /// @param _withUpdate  Mass update all pools if set to true
    /// @param _vault The contract address of the underlying vault
    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _want,
        bool _withUpdate,
        address _vault
    ) public onlyOwner {
        // If _withUpdate provided, update all pools
        if (_withUpdate) {
            massUpdateVaults();
        }

        // Last reward block set to current block, or the start block if the startBlock hasn't been provided
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;

        // Increment the total allocation points by the provided _allocPoint
        totalAllocPoint = totalAllocPoint + _allocPoint;

        // Push to the vaultInfo array
        vaultInfo.push(
            VaultInfo({
                want: _want,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accZORRORewards: 0,
                totalTrancheContributions: 0,
                vault: _vault
            })
        );

        // Update vault mapping
        vaultMapping[_vault] = vaultLength() - 1;
    }

    /// @notice Update the given vault's ZORRO allocation point. Can only be called by the owner.
    /// @param _vid The index of the vault ID
    /// @param _allocPoint The number of allocation points for this vault (aka "multiplier")
    /// @param _withUpdate  Mass update all vaults if set to true
    function set(
        uint256 _vid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        // If _withUpdate provided, update all pools
        if (_withUpdate) {
            massUpdateVaults();
        }
        // Adjust the total allocation points by the provided _allocPoint
        totalAllocPoint = totalAllocPoint - vaultInfo[_vid].allocPoint + _allocPoint;
        // Update the key params for this pool
        vaultInfo[_vid].allocPoint = _allocPoint;
    }

    /// @notice Updates reward variables of all vaults
    /// @dev Be careful of gas fees!
    /// @return _mintedZOR total amount of ZOR rewards minted (useful for cross chain)
    function massUpdateVaults() public returns (uint256 _mintedZOR) {
        uint256 length = vaultInfo.length;
        // Iterate through each pool and run updatePool()
        for (uint256 _vid = 0; _vid < length; ++_vid) {
            _mintedZOR = _mintedZOR + this.updateVault(_vid);
        }
    }
}
