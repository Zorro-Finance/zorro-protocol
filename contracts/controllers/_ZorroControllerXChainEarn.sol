// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./_ZorroControllerXChainBase.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IZorro.sol";

import "../libraries/PriceFeed.sol";

import "../libraries/SafeSwap.sol";

import "./actions/ZorroControllerXChainActions.sol";

contract ZorroControllerXChainEarn is
    IZorroControllerXChainEarn,
    ZorroControllerXChainBase
{
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Modifiers */

    /// @notice Only can be called from a registered vault
    /// @param _pid The pool ID
    modifier onlyRegisteredVault(uint256 _pid) {
        (, , , , , address _vault) = ZorroControllerInvestment(
            currentChainController
        ).poolInfo(_pid);
        require(_msgSender() == _vault, "only reg vault");
        _;
    }

    /// @notice Only can be called on home chain
    modifier onlyHomeChain() {
        require(chainId == homeChainId, "only home chain");
        _;
    }

    /* State */

    // Tokens
    address public zorroLPPoolOtherToken;
    // Contracts
    address public zorroStakingVault;
    address public uniRouterAddress;
    // Paths
    address[] public stablecoinToZorroPath;
    address[] public stablecoinToZorroLPPoolOtherTokenPath;
    // Price feeds
    AggregatorV3Interface public priceFeedZOR;
    AggregatorV3Interface public priceFeedLPPoolOtherToken;
    AggregatorV3Interface public priceFeedStablecoin;
    // Rewards
    uint256 public accumulatedSlashedRewards; // Accumulated ZOR rewards that need to be minted in batch on the home chain. Should reset to zero periodically

    /* Setters */

    function setZorroLPPoolOtherToken(address _token) external onlyOwner {
        zorroLPPoolOtherToken = _token;
    }

    function setZorroStakingVault(address _contract) external onlyOwner {
        zorroStakingVault = _contract;
    }

    function setUniRouterAddress(address _contract) external onlyOwner {
        uniRouterAddress = _contract;
    }

    function setSwapPaths(
        address[] calldata _stablecoinToZorroPath,
        address[] calldata _stablecoinToZorroLPPoolOtherTokenPath
    ) external onlyOwner {
        stablecoinToZorroPath = _stablecoinToZorroPath;
        stablecoinToZorroLPPoolOtherTokenPath = _stablecoinToZorroLPPoolOtherTokenPath;
    }

    function setPriceFeeds(address[] calldata _priceFeeds) external onlyOwner {
        priceFeedZOR = AggregatorV3Interface(_priceFeeds[0]);
        priceFeedLPPoolOtherToken = AggregatorV3Interface(_priceFeeds[1]);
        priceFeedStablecoin = AggregatorV3Interface(_priceFeeds[2]);
    }

    /* Sending */

    /// @notice Sends a request back to the home chain to distribute earnings
    /// @param _pid Pool ID
    /// @param _buybackAmountUSD Amount in USD to buy back
    /// @param _revShareAmountUSD Amount in USD to revshare w/ ZOR single staking vault
    /// @param _maxMarketMovement Acceptable slippage (950 = 5%, 990 = 1% etc.)
    function sendXChainDistributeEarningsRequest(
        uint256 _pid,
        uint256 _buybackAmountUSD,
        uint256 _revShareAmountUSD,
        uint256 _maxMarketMovement
    ) public payable nonReentrant onlyRegisteredVault(_pid) {
        // Require funds to be submitted with this message
        require(msg.value > 0, "No fees submitted");

        // Calculate total USD to transfer
        uint256 _totalUSD = _buybackAmountUSD + _revShareAmountUSD;

        // Transfer USD into this contract
        IERC20Upgradeable(defaultStablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _totalUSD
        );

        // Check balances
        uint256 _balUSD = IERC20Upgradeable(defaultStablecoin).balanceOf(
            address(this)
        );

        // Get accumulated ZOR rewards and set value
        uint256 _slashedRewards = _removeSlashedRewards();

        // Generate payload
        bytes memory _payload = ZorroControllerXChainActions(controllerActions)
            .encodeXChainDistributeEarningsPayload(
                chainId,
                _buybackAmountUSD,
                _revShareAmountUSD,
                _slashedRewards,
                _maxMarketMovement
            );

        // Get the destination contract address on the remote chain
        bytes memory _dstContract = controllerContractsMap[chainId];

        // Call stargate to initiate bridge
        _callStargateSwap(
            StargateSwapPayload({
                chainId: homeChainId,
                qty: _balUSD,
                dstContract: _dstContract,
                payload: _payload,
                maxMarketMovement: _maxMarketMovement
            })
        );
    }

    /* Receiving */

    /// @notice Dummy func to allow .selector call above and guarantee typesafety for abi calls.
    /// @dev Should never ever be actually called.
    function receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) public {
        // Revert to make sure this function never gets called
        require(false, "illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainDistributionRequest(
            _remoteChainId,
            _amountUSDBuyback,
            _amountUSDRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
    }

    /* Fees */

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _remoteChainId The Zorro chain ID of the chain that this request originated from
    /// @param _amountUSDBuyback The amount in USD that should be minted for LP + burn
    /// @param _amountUSDRevShare The amount in USD that should be minted for revenue sharing with ZOR stakers
    /// @param _accSlashedRewards Accumulated slashed rewards on chain
    /// @param _maxMarketMovement factor to account for max market movement/slippage.
    function _receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) internal virtual onlyHomeChain {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(controllerActions, _amountUSDBuyback + _amountUSDRevShare);
        
        // Perform distribution
        ZorroControllerXChainActions(controllerActions).distributeEarnings(
            defaultStablecoin,
            _amountUSDBuyback,
            _amountUSDRevShare,
            _maxMarketMovement,
            ZorroControllerXChainActions.EarningsBuybackParams({
                stablecoin: defaultStablecoin,
                ZORRO: ZORRO,
                zorroLPPoolOtherToken: zorroLPPoolOtherToken,
                burnAddress: burnAddress,
                priceFeedStablecoin: priceFeedStablecoin,
                priceFeedZOR: priceFeedZOR, 
                priceFeedLPPoolOtherToken: priceFeedLPPoolOtherToken, 
                stablecoinToZorroPath: stablecoinToZorroPath, 
                stablecoinToZorroLPPoolOtherTokenPath: stablecoinToZorroLPPoolOtherTokenPath
            }),
            ZorroControllerXChainActions.EarningsRevshareParams({
                stablecoin: defaultStablecoin,
                ZORRO: ZORRO,
                zorroLPPoolOtherToken: zorroLPPoolOtherToken, 
                zorroStakingVault: zorroStakingVault,
                priceFeedStablecoin: priceFeedStablecoin, 
                priceFeedZOR: priceFeedZOR,
                stablecoinToZorroPath: stablecoinToZorroPath 
            })
        );

        // Emit event
        emit XChainDistributeEarnings(
            _remoteChainId,
            _amountUSDBuyback,
            _amountUSDRevShare
        );

        // Award slashed rewards to ZOR stakers
        if (_accSlashedRewards > 0) {
            _awardSlashedRewardsToStakers(_accSlashedRewards);
        }
    }


    /* Slashed rewards */

    /// @notice Called by oracle to remove slashed ZOR rewards and reset
    /// @return _slashedZORRewards The amount of accumulated slashed ZOR rewards
    function _removeSlashedRewards()
        internal
        returns (uint256 _slashedZORRewards)
    {
        // Store current rewards amount
        _slashedZORRewards = accumulatedSlashedRewards;

        // Emit success event
        emit RemovedSlashedRewards(_slashedZORRewards);

        // Reset accumulated rewards
        accumulatedSlashedRewards = 0;
    }

    /// @notice Awards the slashed ZOR rewards from other chains to this (home) chain's ZOR staking vault
    /// @param _slashedZORRewards The amount of accumulated slashed ZOR rewards
    function _awardSlashedRewardsToStakers(uint256 _slashedZORRewards)
        internal
    {
        // Mint ZOR and send to ZOR staking vault.
        IZorro(ZORRO).mint(zorroStakingVault, _slashedZORRewards);
    }
}
