// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./_ZorroControllerInvestment.sol";

import "../interfaces/IVault.sol";

import "../interfaces/LayerZero/ILayerZeroEndpoint.sol";

import "../interfaces/Stargate/IStargateRouter.sol";

import "../interfaces/IZorroControllerXChain.sol";

contract ZorroControllerXChainBase is
    IZorroControllerXChainBase,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* State */

    // Stargate/LZ
    address public stargateRouter; // Address to on-chain Stargate router
    uint256 public stargateSwapPoolId; // Address of the pool to swap from on this contract
    mapping(uint256 => uint256) public stargateDestPoolIds; // Mapping from Zorro chain ID to Stargate dest Pool for the same token
    address public layerZeroEndpoint; // Address to on-chain LayerZero endpoint
    // Chain maps
    mapping(uint256 => bytes) public controllerContractsMap; // Mapping of Zorro chain ID to endpoint contract
    mapping(uint256 => uint16) public ZorroChainToLZMap; // Mapping of Zorro Chain ID to Stargate/LayerZero Chain ID
    mapping(uint16 => uint256) public LZChainToZorroMap; // Mapping of Stargate/LayerZero Chain ID to Zorro Chain ID
    mapping(uint256 => uint256) public chainTypes; // Mapping of Zorro Chain ID to chain type. 0: EVM, 1: Solana
    // Tokens
    address public defaultStablecoin;
    address public ZORRO;
    // Contracts
    address public homeChainZorroController;
    address public currentChainController;
    address public publicPool;
    address public controllerActions; // TODO: Setter and constructor
    // Chain config
    uint256 public chainId;
    uint256 public homeChainId;
    // Other
    address public burnAddress; // Address to send funds to, to burn them

    /* Setters */

    function setTokens(address[] calldata _tokens) external onlyOwner {
        defaultStablecoin = _tokens[0];
        ZORRO = _tokens[1];
    }

    function setKeyContracts(address[] calldata _contracts) external onlyOwner {
        homeChainZorroController = _contracts[0];
        currentChainController = _contracts[1];
        publicPool = _contracts[2];
    }

    function setChains(uint256[] calldata _chainIds) external onlyOwner {
        chainId = _chainIds[0];
        homeChainId = _chainIds[1];
    }

    /// @notice Setter: Controller contract for each chain
    /// @param _zorroChainId Zorro Chain ID
    /// @param _controller Bytes representation of smart contract address for cross chain contract
    function setControllerContract(
        uint256 _zorroChainId,
        bytes calldata _controller
    ) external onlyOwner {
        controllerContractsMap[_zorroChainId] = _controller;
    }

    /// @notice Setter: LZ/Stargate params
    /// @param _zorroChainId Zorro chain ID
    /// @param _lzChainId LayerZero Chain ID
    function setZorroChainToLZMap(uint256 _zorroChainId, uint16 _lzChainId)
        external
        onlyOwner
    {
        ZorroChainToLZMap[_zorroChainId] = _lzChainId;
        LZChainToZorroMap[_lzChainId] = _zorroChainId;
    }

    /// @notice Setter: Stargate dest pool IDs for USD asset
    /// @param _zorroChainId Zorro chain ID
    /// @param _stargatePoolId Stargate pool ID
    function setStargateDestPoolIds(
        uint256 _zorroChainId,
        uint16 _stargatePoolId
    ) external onlyOwner {
        stargateDestPoolIds[_zorroChainId] = _stargatePoolId;
    }

    /// @notice Setter: Set main LZ params
    //// @param _stargateRouter Address of Stargate router contract
    //// @param _stargateSwapPoolId ID of Stargate swap pool for stablecoin asset
    //// @param _layerZeroEndpoint Layer Zero main endpoint on chain
    function setLayerZeroParams(
        address _stargateRouter,
        uint256 _stargateSwapPoolId,
        address _layerZeroEndpoint
    ) external onlyOwner {
        stargateRouter = _stargateRouter;
        stargateSwapPoolId = _stargateSwapPoolId;
        layerZeroEndpoint = _layerZeroEndpoint;
    }

    function setChainType(uint256 _zorroChainId, uint256 _chainType)
        external
        onlyOwner
    {
        chainTypes[_zorroChainId] = _chainType;
    }

    function setBurnAddress(address _burn) external onlyOwner {
        burnAddress = _burn;
    }

    /* Router functions */

    /// @notice Internal function for making swap calls to Stargate
    /// @param _swapPayload Struct with key swap payload information for the call to the Stargate router
    function _callStargateSwap(StargateSwapPayload memory _swapPayload)
        internal
    {
        // Approve spending by Stargate
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            stargateRouter,
            _swapPayload.qty
        );

        // Swap call
        IStargateRouter.lzTxObj memory _lzTxObj;
        IStargateRouter(stargateRouter).swap{value: msg.value}(
            ZorroChainToLZMap[_swapPayload.chainId],
            stargateSwapPoolId,
            stargateDestPoolIds[_swapPayload.chainId],
            payable(msg.sender),
            _swapPayload.qty,
            (_swapPayload.qty * _swapPayload.maxMarketMovement) / 1000,
            _lzTxObj,
            _swapPayload.dstContract,
            _swapPayload.payload
        );
    }

    /// @notice Internal function for sending cross chain messages using LayerZero
    /// @param _msgPayload Struct with key message details for the LayerZero cross chain transaction
    function _callLZSend(LZMessagePayload memory _msgPayload) internal {
        // Convert any key params
        uint16 _dstChainId = ZorroChainToLZMap[_msgPayload.zorroChainId];

        // Send transaction to layer
        ILayerZeroEndpoint(layerZeroEndpoint).send{value: msg.value}(
            _dstChainId,
            _msgPayload.destinationContract,
            _msgPayload.payload,
            _msgPayload.refundAddress,
            _msgPayload.refundAddress,
            _msgPayload.adapterParams
        );
    }
}
