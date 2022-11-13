// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultBenqiLiqStakeLP.sol";

import "../../interfaces/Benqi/IStakedAvax.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockVaultBenqiLiqStakeLP is VaultBenqiLiqStakeLP {
    // TODO: Fill out any necessary methods for testing here
}

// TODO: Fill out below
contract MockBenqiLiqStakePoolAVAX is IStakedAvax, ERC20Upgradeable {
    function getSharesByPooledAvax(uint avaxAmount) external view returns (uint) {

    }

    function getPooledAvaxByShares(uint shareAmount) external view returns (uint) {

    }

    function submit() external payable returns (uint) {

    }

    function deposit() external payable {

    }
}