// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.12 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

enum SwapKind { GIVEN_IN, GIVEN_OUT }

/// @dev This is an empty interface used to represent either ERC20-conforming token contracts or ETH (using the zero
interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

interface IBalancerVault {
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountCalculated);

    function getPoolTokenInfo(bytes32 poolId, IERC20 token) 
        external
        returns (uint256 cash, uint256 managed, uint256 blockNumber, address assetManager);
}