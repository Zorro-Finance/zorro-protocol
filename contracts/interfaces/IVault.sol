// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/* For interacting with our own Vaults */
interface IVault {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    // Note: Earn events do not happen here. They are triggered via CRON
    function earn() external;

    // Transfer Want tokens into Vault
    function deposit(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer Want tokens from Vault
    function withdraw(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer ERC20 tokens on the Vault back to the owner, if necessary
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}