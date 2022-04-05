// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../helpers/ModifiedPaymentSplitter.sol";

import "../helpers/ModifiedVestingWallet.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// TODO: Make sure this is inline with our latest vesting (e.g. Josh contract) 

/// @title PoolTeam: Manages the team (employee/advisors) pool via a modified PaymentSplitter contract
contract PoolTeam is ModifiedPaymentSplitter, Ownable {
    using SafeMath for uint256;

    /* State */
    address public ZORRO;
    address public reservePool;

    /* Events */
    event PayeeRemoved(address indexed _payee, uint256 indexed _unvestedShares);

    /* Constructor */

    /// @notice Constructor. Initializes by assigning all shares to a reserve contract initially.
    /// @param _zorroToken address of the Zorro token
    /// @param _timelockOwner address of the owner (TimelockController)
    /// @param _reserveAddresses a single item array containing the address of the reserve pool from which shares are obtained for new payees
    /// @param _initialShares a single item array containing the initial number of shares
    constructor(address _zorroToken, address _timelockOwner, address[] memory _reserveAddresses, uint256[] memory _initialShares)
        payable
        ModifiedPaymentSplitter(_reserveAddresses, _initialShares)
    {
        // Set reserve pool address
        reservePool = _reserveAddresses[0];
        // Set the Zorro token address
        ZORRO = _zorroToken;
        // Set the owner to the TimelockController
        transferOwnership(_timelockOwner);
    }

    /// @notice Adds a payee. 
    /// @param _payee Address of new payee
    /// @param _sharesRequested Number of shares to assign 
    function addPayee(address _payee, uint256 _sharesRequested) public onlyOwner {
      // Safety: ensure number of shares requested is available in the reserve pool
      require(_sharesRequested <= shares(reservePool), "Not enough shares in reserve");
      // Decrease the shares of the reserve pool by specified shares
      _shares[reservePool] = _shares[reservePool].sub(_sharesRequested);
      // Add the payee
      _addPayee(_payee, _sharesRequested);
      // Correct the total shares (_addPayee() increases the total shares but this is not valid because we are actually only transferring from the reserve)
      _totalShares = _totalShares.sub(_sharesRequested);
      // Notify with event
      emit PayeeAdded(_payee, _sharesRequested);
    }

    /// @notice Removes a payee. 
    /// @param _payee Address of new payee
    function removePayee(address payable _payee) public onlyOwner {
      // Call the release() function to send all outstanding funds to the payee's VestingWallet
      release(IERC20(ZORRO), _payee);
      // Get the payee's current number of shares
      uint256 payeeShares = shares(_payee);
      // Call the payee's VestingWallet's stopVesting() function to release vested funds and pay unvested funds back to this contract, replenishing the pool.
      (uint256 unvestedAmt, uint256 releasedAmt) = TeamMemberVestingWallet(_payee).stopVesting();
      // Calculate the number of unused shares by payee
      uint256 unusedShares = payeeShares.mul(unvestedAmt).div(unvestedAmt.add(releasedAmt));
      // Send unused shares to reserve for future allocation
      _shares[reservePool] = _shares[reservePool].add(unusedShares);
      // Set payee shares to zero
      _shares[_payee] = 0;
      // Update total shares
      _totalShares = _totalShares.sub(payeeShares).add(unusedShares);
      // Notify of payee removal
      emit PayeeRemoved(_payee, unusedShares);
    }
}

/// @title TeamMemberVestingWallet: Modified version of the VestingWallet that allows for stopping vesting and returning unvested funds
contract TeamMemberVestingWallet is ModifiedVestingWallet, Ownable {
  using SafeERC20 for IERC20;
    /* Constructor */

    /// @notice Constructor. Sets vesting parameters and assigns ownership, etc.
    /// @param _zorroToken address of the Zorro token
    /// @param _owner address of the PoolTeam contract that should own this contract
    /// @param beneficiaryAddress address of the end user wallet that should ultimately receive the vested funds
    /// @param startTimestamp the unix timestamp at which vesting is to have begun
    /// @param durationSeconds the vesting period in seconds
    constructor(
        address _zorroToken,
        address _owner,
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds
    )
        ModifiedVestingWallet(
            beneficiaryAddress,
            startTimestamp,
            durationSeconds
        )
    {
        // Set Zorro token address
        ZORRO = _zorroToken;
        // Set owner
        transferOwnership(_owner);
    }

    /* State */
    address public ZORRO;
    bool public shouldVest = true;

    /* Functions */

    /// @notice Used to stop vesting of ERC20 token. Releases vested funds, sends unvested funds back to owner. NOTE: No more funds should be sent to this address once called
    /// @return unvested amount, released amount
    function stopVesting() public onlyOwner returns (uint256, uint256) {
        // 1) Releases vested funds for specified account
        release(ZORRO);
        // Get released amount
        uint256 releasedAmount = released(address(this));
        // Get unvested amount (remaining balance)
        uint256 unvestedAmount = IERC20(ZORRO).balanceOf(address(this));
        // 2) Sends unvested funds back to the controller PaymentSplitter contract 
        IERC20(ZORRO).safeTransfer(owner(), unvestedAmount);
        return (unvestedAmount, releasedAmount);
    }
}
