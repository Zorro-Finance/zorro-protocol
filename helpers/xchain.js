// Helper for xChain tests (to be deployed and run on testnet)

const { zeroAddress } = require("./constants");

/*
1. Run migrate on testnet
2. Run truffle console
3. Run require('./helpers/xchain.js') (this file)
4. Run setup() on each chain
5. Get USD if necessary (Faucet: https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/testnet-faucet)
6. Call send*() function on origin chain
7. Call receive*() function immediately on destination chain to listen for sent xchain payload
*/

// Migration
const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
// TODO: Other contract artifacts

/* Setup */

exports.setup = async (network) => {
    // TODO

    // Deployed contracts
    // TODO

    // Network dependent setup
    if (network === 'avaxtest') {
        // Prep constructor
        const initVal = {
            defaultStablecoin: tokens.busd,
            ZORRO: zorro.address,
            zorroLPPoolOtherToken: tokens.wbnb,
            zorroStakingVault: zeroAddress, // Must be set later
            uniRouterAddress: infra.uniRouterAddress,
            homeChainZorroController: zorroController.address,
            currentChainController: zorroController.address,
            publicPool: zeroAddress, // Must be set later
            controllerActions: zorroControllerXChainActions.address,
            bridge: {
                chainId: xChain.chainId,
                homeChainId: xChain.homeChainId,
                ZorroChainIDs: [xChain.chainId],
                controllerContracts: [zorroController.address],
                LZChainIDs: [xChain.lzChainId],
                stargateDestPoolIds: [xChain.sgPoolId],
                stargateRouter: infra.stargateRouter,
                layerZeroEndpoint: infra.layerZeroEndpoint,
                stargateSwapPoolId: 0, // TODO: Change this to the real value. It's just a placeholder
            },
            swaps: {
                stablecoinToZorroPath: [],
                stablecoinToZorroLPPoolOtherTokenPath: [],
            },
            priceFeeds: {
                priceFeedZOR: zeroAddress,
                priceFeedLPPoolOtherToken: priceFeeds.bnb,
                priceFeedStablecoin: priceFeeds.busd,
            },
        };
    } else if (network === 'bnbtest') {
        // Prep constructor
        const initVal = {
    
        };
    }

    // Deploy contract locally
    await MockZorroControllerXChain.new(initVal);
};

/* Deposits */

// Send deposit //

exports.sendDeposit = async () => {
    // Allow spending of USD
    // Encode payload via encodeXChainDepositPayload
    // Check fee via checkXChainDepositFee
    // Call sendXChainDepositRequest
};

// Check receive deposit //
exports.receiveDeposit = async () => {
    // Listen for ReceiveXChainDepositReq event, ensure all event params match what was sent over
    // Upon receipt, check to see balance of USD, ensure matches the amount sent minus fee
};

/* Withdrawals */

// Send withdrawal request //
exports.sendWithdrawalRequest = async () => {
    // Encode payload via encodeXChainDepositPayload
    // Check fee via checkXChainWithdrawalFee
    // Call encodeXChainWithdrawalPayload
};


// Check receive withdrawal request //
exports.receiveWithdrawal = async () => {
    // Listen for ReceiveXChainWithdrawalReq event, ensure all params match what was sent
};

/* Utilities */

// Get USD (stablecoin) from native
exports.mintStablecoin = async (network, amount) => {
    // Get stablecoin ERC20 address
    if (network === 'avaxtest') {
        const stablecoinAddress = '0x4A0D1092E9df255cf95D72834Ea9255132782318';
    } else if (network === 'bnbtest') {
        const stablecoinAddress = '0xF49E250aEB5abDf660d643583AdFd0be41464EfD';
    }

    // TODO: call ERC20.mint() function and send to self
};

