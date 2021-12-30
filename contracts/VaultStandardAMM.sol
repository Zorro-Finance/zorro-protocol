// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ERC20.sol";

import "./libraries/Address.sol";

import "./libraries/EnumerableSet.sol";

import "./interfaces/IAMMFarm.sol";

import "./VaultBase.sol";

import "./interfaces/IERC20.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/SafeMath.sol";


/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
abstract contract VaultStandardAMM is VaultBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return Number of shares added
    function deposit(uint256 _wantAmt) public virtual onlyOwner nonReentrant whenNotPaused returns (uint256) {
        // Transfer Want token from current user to this contract
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );
        // Set sharesAdded to the Want token amount specified
        uint256 sharesAdded = _wantAmt;
        // If the total number of shares and want tokens locked both exceed 0, the shares added is the proportion of Want tokens locked, 
        // discounted by the entrance fee 
        if (wantLockedTotal > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(wantLockedTotal)
                .div(entranceFeeFactorMax);
        }
        // Increment the shares
        sharesTotal = sharesTotal.add(sharesAdded);

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    /// @notice Public function for farming Want token. 
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal virtual {
        // Farming should only occur if this contract is set for autocompounding
        require(isZorroComp, "!isZorroComp");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        if (isCOREStaking) {
            // If this contract is meant for staking a core asset of the underlying protocol (e.g. CAKE on Pancakeswap, BANANA on Apeswap),
            // Stake that token in a single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).enterStaking(wantAmt);
        } else {
            // Otherwise deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
            IAMMFarm(farmContractAddress).deposit(pid, wantAmt);
        }
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal virtual {
        if (isCOREStaking) {
            // If this is contract is meant for staking a core assets of the underlying protocol, 
            // simply un-stake the asset from the single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
        } else {
            // Otherwise simply withdraw the Want tokens from the Farm contract pool
            IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
    }

    /// @notice Withdraw Want tokens from the Farm contract
    /// @param _wantAmt the amount of Want tokens to withdraw
    /// @return the number of shares removed
    function withdraw(uint256 _wantAmt) public virtual onlyOwner nonReentrant returns (uint256) {
        // Want amount must be greater than 0
        require(_wantAmt > 0, "_wantAmt <= 0");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // If this contract is designated for auto compounding, unfarm the Want tokens
        if (isZorroComp) {
            _unfarm(_wantAmt);
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }
        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return sharesRemoved;
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event. 
    function earn() public virtual nonReentrant whenNotPaused {
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // If the earned address is the WBNB token, wrap all BNB owned by this contract
        if (earnedAddress == wbnbAddress) {
            _wrapBNB();
        }

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Reassign value of earned amount after distributing fees
        earnedAmt = distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro
        earnedAmt = buyBack(earnedAmt);

        // If staking a single token (CAKE, BANANA), farm that token and exit
        if (isCOREStaking || isSameAssetDeposit) {
            // Update the last earn block
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        // Approve the router contract 
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        // Allow the router contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, earnedAmt);

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            _safeSwap(
                uniRouterAddress,
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            _safeSwap(
                uniRouterAddress,
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken1Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Increase the allowance of the router to spend token0
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            // Increase the allowance of the router to spend token1
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            // Add liquidity
            IAMMRouter02(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }
}
