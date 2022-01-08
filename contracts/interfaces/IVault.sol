// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/* For interacting with our own Vaults */
interface IVault {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Deposits
    function exchangeUSDForWantToken(address _account, uint256 _amount, uint256 _maxMarketMovementAllowed) external returns (uint256, bool);

    function depositWantToken(uint256 _wantAmt) external returns (uint256);

    // Withdrawals
    function withdrawWantToken(uint256 _wantAmt) external returns (uint256);

    function exchangeWantTokenForUSD(address _account, uint256 _amount, uint256 _maxMarketMovementAllowed) external returns (uint256, bool);

    // Claims
    function settleTrades(address _user, uint256 _settlementEpoch, address _token) external returns (uint256);

    // Compounding
    function earn() external;

    // Transfer ERC20 tokens on the Vault back to the owner, if necessary
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}