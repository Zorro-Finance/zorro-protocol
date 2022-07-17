// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../SafeSwap.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../tokens/mocks/MockToken.sol";

/// @title MockSafeSwapUni: Mock contract for testing the SafeSwapUni library
contract MockSafeSwapUni {
    using SafeSwapUni for IAMMRouter02;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function safeSwap(
        address _uniRouter,
        uint256 _amountIn,
        uint256 _priceTokenIn,
        uint256 _priceTokenOut,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) public {
        // Give permission
        IERC20Upgradeable(_path[0]).safeIncreaseAllowance(
            _uniRouter,
            _amountIn
        );
        // Swap
        IAMMRouter02(_uniRouter).safeSwap(
            _amountIn,
            _priceTokenIn,
            _priceTokenOut,
            _slippageFactor,
            _path,
            _to,
            _deadline
        );
    }
}

/// @title MockAMMRouter02: Mock contract for the IAMMRouter02 library
contract MockAMMRouter02 is IAMMRouter02, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public burnAddress;
    address public poolAddress;
    uint256 private _dummy; // Used to satisfy state mutability compiler warnings on Mock contracts

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function setPoolAddress(address _poolAddress) public {
        poolAddress = _poolAddress;
    }

    event SwappedToken(
        address indexed _dest,
        uint256 indexed _amountIn,
        uint256 indexed _amountOutMin
    );

    event AddedLiquidity(
        uint256 indexed _amountA,
        uint256 indexed _amountB,
        uint256 indexed _liquidity
    );

    event RemovedLiquidity(uint256 indexed _amountA, uint256 indexed _amountB);

    function factory() external pure returns (address) {
        return address(0);
    }

    function WETH() external pure returns (address) {
        return address(0);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        // Requirements
        require(amountAMin >= 0 && amountBMin >= 0 && deadline > 0);

        // Vars
        amountA = amountADesired;
        amountB = amountBDesired;
        // Safe transfer from
        IERC20Upgradeable(tokenA).safeTransferFrom(
            msg.sender,
            address(this),
            amountA
        );
        IERC20Upgradeable(tokenB).safeTransferFrom(
            msg.sender,
            address(this),
            amountB
        );

        // Mint LP token (just 1 token for simplicity)
        liquidity = 1 ether;
        IMockERC20Upgradeable(address(this)).mint(to, liquidity);

        // Emit event
        emit AddedLiquidity(amountA, amountB, liquidity);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {}

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        // Requirements
        require(deadline > 0);

        // Vars
        amountA = amountAMin;
        amountB = amountBMin;

        // Safe transfer liquidity & burn
        IERC20Upgradeable(poolAddress).safeTransferFrom(
            msg.sender,
            burnAddress,
            liquidity
        );

        // Mint tokens 0, 1
        IMockERC20Upgradeable(tokenA).mint(to, amountA);
        IMockERC20Upgradeable(tokenB).mint(to, amountB);

        // Emit event
        emit RemovedLiquidity(amountA, amountB);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH) {}

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {}

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {}

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        return
            _mockSwapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function _mockSwapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) internal returns (uint256[] memory amounts) {
        // Reqs
        require(deadline > 0);

        // Vars
        address _tokenIn = path[0];
        address _tokenOut = path[path.length - 1];

        // Burn token IN
        IERC20Upgradeable(_tokenIn).safeTransferFrom(
            msg.sender,
            burnAddress,
            amountIn
        );

        // Mint token OUT -> to
        IMockERC20Upgradeable(_tokenOut).mint(to, amountOutMin);

        // Return
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = amountIn;
        _amounts[1] = amountOutMin;
        amounts = _amounts;

        emit SwappedToken(msg.sender, amountIn, amountOutMin);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {}

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {}

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB) {}

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        // Reqs
        require(reserveIn >= 0 && reserveOut >= 0);

        return amountIn;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn) {}

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        // Reqs, satisfy compiler state mutability errors
        require(path.length > 0 && _dummy >= 0);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = amountIn;
        return _amounts;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {}

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH) {}

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH) {}

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        _mockSwapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable {}

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {}
}

/// @title MockSafeSwapBalancer: Mock contract for testing the SafeSwapBalancer library
contract MockSafeSwapBalancer {
    using SafeSwapBalancer for IBalancerVault;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function safeSwap(
        address _balancerVault,
        bytes32 _poolId,
        SafeSwapParams memory _swapParams
    ) public {
        IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
            _balancerVault,
            _swapParams.amountIn
        );
        IBalancerVault(_balancerVault).safeSwap(_poolId, _swapParams);
    }
}

/// @title MockBalancerVault: Mock contract for the IBalancerVault library
contract MockBalancerVault is IBalancerVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event SwappedToken(
        address indexed _dest,
        uint256 indexed amountIn,
        uint256 indexed minAmountOut
    );

    mapping(address => uint256) internal _cash;
    address public burnAddress;
    uint256 private _dummy; // For compiler state mutability satisfaction

    function setCash(address _token, uint256 _amount) public {
        _cash[_token] = _amount;
    }

    function setBurnAddress(address _burn) public {
        burnAddress = _burn;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated) {
        // Reqs
        require(deadline > 0);

        // Burn token IN
        IERC20Upgradeable(address(singleSwap.assetIn)).safeTransferFrom(
            msg.sender,
            burnAddress,
            singleSwap.amount
        );

        // Mint token OUT -> to
        IMockERC20Upgradeable(address(singleSwap.assetOut)).mint(
            funds.recipient,
            limit
        );

        // Event
        emit SwappedToken(funds.recipient, singleSwap.amount, limit);

        // Return
        amountCalculated = limit;
    }

    function getPoolTokenInfo(bytes32 poolId, IERC20 token)
        external
        returns (
            uint256 cash,
            uint256 managed,
            uint256 blockNumber,
            address assetManager
        )
    {
        // Reqs
        require(abi.encode(poolId).length >= 0); // Satisfy unused variable warning
        require(managed >= 0 && blockNumber > 0 && assetManager != address(0));
        _dummy = 0;

        cash = _cash[address(token)];
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        )
    {}

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external {}

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external {}
}
