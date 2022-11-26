// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMFarm.sol";

import "../interfaces/Stargate/IStargateRouter.sol";

import "../interfaces/Stargate/IStargateLPStaking.sol";

import "../interfaces/Zorro/Vaults/IVaultStargate.sol";

import "./actions/VaultActionsStargate.sol";

import "./_VaultBase.sol";

/// @title Vault contract for Stargate single token strategies (e.g. for lending bridgeable tokens)
contract VaultStargate is IVaultStargate, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStargateInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStargateInit memory _initValue
    ) public initializer {
        // Vault config
        pid = _initValue.pid;
        isHomeChain = _initValue.isHomeChain;
        isFarmable = _initValue.isFarmable;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        zorroXChainController = _initValue.keyAddresses.zorroXChainController;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        zorroStakingVault = _initValue.keyAddresses.zorroStakingVault;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        token1Address = _initValue.keyAddresses.token1Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
        stargateRouter = _initValue.stargateRouter;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;
        tokenSTG = _initValue.tokenSTG;
        stargatePoolId = _initValue.stargatePoolId;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        _setSwapPaths(_initValue.earnedToZORROPath);
        _setSwapPaths(_initValue.earnedToToken0Path);
        _setSwapPaths(_initValue.stablecoinToToken0Path);
        _setSwapPaths(_initValue
            .earnedToZORLPPoolOtherTokenPath);
        _setSwapPaths(_initValue.earnedToStablecoinPath);
        // Corresponding reverse paths
        _setSwapPaths(VaultActions(vaultActions).reversePath(
            _initValue.stablecoinToToken0Path
        ));

        // Price feeds
        _setPriceFeed(token0Address, _initValue.priceFeeds.token0PriceFeed);
        _setPriceFeed(earnedAddress, _initValue.priceFeeds.earnTokenPriceFeed);
        _setPriceFeed(zorroLPPoolOtherToken, _initValue.priceFeeds.lpPoolOtherTokenPriceFeed);
        _setPriceFeed(defaultStablecoin, _initValue.priceFeeds.stablecoinPriceFeed);

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* State */

    address public tokenSTG; // Stargate token
    address public stargateRouter; // Stargate Router for adding/removing liquidity etc.
    uint16 public stargatePoolId; // Stargate Pool that tokens shall be lent to

    /* Setters */

    function setTokenSTG(address _token) external onlyOwner {
        tokenSTG = _token;
    }

    function setStargatePoolId(uint16 _poolId) external onlyOwner {
        stargatePoolId = _poolId;
    }

    function setStargateRouter(address _router) external onlyOwner {
        stargateRouter = _router;
    }

    /* Investment Actions */

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public onlyZorroController whenNotPaused returns (uint256) {
        // Allow spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsStargate(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsStargate.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    tokenZorroAddress: ZORROAddress,
                    token0PriceFeed: priceFeeds[token0Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToToken0Path: swapPaths[defaultStablecoin][token0Address],
                    stargateRouter: stargateRouter,
                    wantAddress: wantAddress,
                    stargatePoolId: stargatePoolId
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        require(isFarmable, "!farmable");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            wantAmt
        );

        // Deposit the Want tokens in the Farm contract
        IStargateLPStaking(farmContractAddress).deposit(pid, wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        // Withdraw the Want tokens from the Farm contract
        IStargateLPStaking(farmContractAddress).withdraw(pid, _wantAmt);
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        onlyZorroController
        whenNotPaused
        returns (uint256)
    {
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Exchange
        return
            VaultActionsStargate(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsStargate.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    wantAddress: wantAddress,
                    stargateRouter: stargateRouter,
                    token0PriceFeed: priceFeeds[token0Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    token0ToStablecoinPath: swapPaths[token0Address][defaultStablecoin],
                    stargatePoolId: stargatePoolId
                }),
                _maxMarketMovementAllowed
            );
    }
}

contract StargateUSDCOnAVAX is VaultStargate {}
