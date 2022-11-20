// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultStargate.sol";

import "../../tokens/mocks/MockToken.sol";

// import "../libraries/VaultLibrary.sol";

contract MockVaultStargate is VaultStargate {
    function unfarm(uint256 _wantAmt) public {
        _unfarm(_wantAmt);
    }
}

contract MockStargateRouter is IStargateRouter, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public burnAddress;
    address public stargatePool;
    address public asset;
    uint256 private _dummy; // Satisfy compiler state mutability warnings

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function setStargatePool(address _pool) public {
        stargatePool = _pool;
    }

    function setAsset(address _token) public {
        asset = _token;
    }

    event SwappedToken(
        address indexed _dest,
        uint256 indexed _amountIn,
        uint256 indexed _amountOutMin
    );

    event AddedLiquidity(uint256 indexed _amount, uint256 indexed _liquidity);

    event RemovedLiquidity(uint256 indexed _amount);

    event SgSwapped(uint256 indexed _chainId, uint256 indexed _qty, bytes indexed _dstContract);

    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external {
        // Reqs
        require(_poolId >= 0);

        // Transfer funds & burn
        IERC20Upgradeable(asset).safeTransferFrom(
            msg.sender,
            burnAddress,
            _amountLD
        );

        // Mint some LP token
        uint256 _liquidity = 1 ether; // Hard code 1 token for simplicity
        // Transfer LP token
        IMockERC20Upgradeable(stargatePool).mint(_to, _liquidity);
        // Log liquidity addition
        emit AddedLiquidity(_amountLD, _liquidity);
    }

    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable {
        // Reqs
        require(_srcPoolId >= 0 && _dstPoolId >= 0);
        require(_refundAddress != address(0));
        require(_lzTxParams.dstGasForCall >= 0);
        require(_payload.length >= 0);

        // Transfer to burn
        IERC20Upgradeable(asset).safeTransferFrom(msg.sender, burnAddress, _amountLD);
        // Log
        emit SgSwapped(_dstChainId, _minAmountLD, _to);
    }

    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable {}

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external returns (uint256) {
        // Reqs
        require(_srcPoolId >= 0);

        // Safe transfer liquidity and burn
        IERC20Upgradeable(stargatePool).safeTransferFrom(
            msg.sender,
            burnAddress,
            _amountLP
        );

        // Mint asset token
        uint256 _amount = 2 ether; // Hardcode for simplicity/testing
        IMockERC20Upgradeable(asset).mint(_to, _amount);
        // Log removed equidity
        emit RemovedLiquidity(_amount);
        // Return
        return _amount;
    }

    function redeemLocal(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable {}

    function sendCredits(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress
    ) external payable {}

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256) {
        // Reqs
        require(_dstChainId >= 0 && _functionType >= 0);
        require(_toAddress.length >= 0 && _transferAndCallPayload.length >= 0);
        require(_lzTxParams.dstGasForCall >= 0);
        require(_dummy >= 0);

        return (0.01 ether, 0.02 ether); // Hardcoded for tests
    }
}

contract MockStargatePool is MockERC20Upgradeable {}

contract MockStargateLPStaking is IStargateLPStaking {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposited(address indexed _want, uint256 indexed _amount);
    event Withdrew(address indexed _want, uint256 indexed _amount);

    address public burnAddress;
    address public wantToken;

    function setWantAddress(address _wantToken) public {
        wantToken = _wantToken;
    }

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function deposit(uint256 _pid, uint256 _amount) external {
        // Reqs
        require(_pid >= 0);

        IERC20Upgradeable(wantToken).safeTransferFrom(msg.sender, burnAddress, _amount);
        emit Deposited(wantToken, _amount);        
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        // Reqs
        require(_pid >= 0);

        IMockERC20Upgradeable(wantToken).mint(msg.sender, _amount);
        emit Withdrew(wantToken, _amount);
    }
}

contract MockSTGToken is MockERC20Upgradeable {}