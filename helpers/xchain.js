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
// const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
// const ZorroControllerXChainActions = artifacts.require('ZorroControllerXChainActions');
// const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');

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

exports.sendDeposit = async (zcx, zcxa, usdc, web3, accounts) => {
    // Get instance of deployed x chain contract
    // const zcx = await MockZorroControllerXChain.deployed();
    // const zcxa = await ZorroControllerXChainActions.deployed();

    // Encode payload via encodeXChainDepositPayload
    const wallet = '0x051D87B2a00451c2463F8A5EFEFBF54d8945Cf0c'; // Truffle wallet testing
    // const depositUSDC = web3.utils.toBN(web3.utils.toWei('1', 'micro'));
    const depositUSDC = '10'
    const payload = web3.eth.abi.encodeFunctionCall({
        name: 'receiveXChainDepositRequest',
        type: 'function',
        inputs: [
            {type: 'uint256', name: '_vid'},
            {type: 'uint256', name: '_valueUSD'},
            {type: 'uint256', name: '_weeksCommitted'},
            {type: 'uint256', name: '_maxMarketMovement'},
            {type: 'address', name: '_originWallet'},
            {type: 'bytes', name: '_destWallet'},
        ],
    }, [
        0,
        depositUSDC,
        0,
        990,
        wallet,
        wallet,
    ]);

    console.log('deposit payload: ', payload);

    // Check fee via checkXChainDepositFee
    const nativeFee = await zcxa.checkXChainDepositFee.call(
        10102, // BNB
        '0xCbaF3d0193b5f3ad92F39E7E4Efa6EBA2D211BA3', // ZCX contract on BNB side
        payload
    );

    console.log('native fee: ', nativeFee.toString());

    // Approve spending of USDC
    await usdc.approve(zcx.address, depositUSDC);

    // Call sendXChainDepositRequest
    await zcx.sendXChainDepositRequest(
        10102,
        0,
        depositUSDC,
        0,
        990,
        wallet,
        {   from: accounts[0],
            value: nativeFee,
        }
    );
};

// Clear stuck tx on destination chain
exports.clearDestTx = async (stgRouterAddr, srcAddress, nonce, web3, accounts) => {
    // Prep call to clearCachedSwap
    const data = web3.eth.abi.encodeFunctionCall({
        name: 'clearCachedSwap',
        type: 'function',
        inputs: [{
            type: 'uint16',
            name: '_srcChainId',
        }, {
            type: 'bytes',
            name: '_srcAddress',
        }, {
            type: 'uint256',
            name: '_nonce',
        }],
    }, [
        10106,
        srcAddress,
        nonce,
    ]);

    // Send transcation
    return web3.eth.sendTransaction({
        from: accounts[0],
        data,
        to: stgRouterAddr,
    });
};

// Check receive deposit //
exports.receiveDeposit = async (zcx, busd, web3, hexString, topics) => {
    // Listen for ReceiveXChainDepositReq event, ensure all event params match what was sent over
    const inputs = [
        {
            type: 'uint256',
            name: '_vid',
            indexed: true,
        },
        {
            type: 'uint256',
            name: '_valueUSD',
            indexed: true,
        },
        {
            type: 'address',
            name: '_destAccount',
            indexed: true,
        },
    ];

    const decodedLog = web3.eth.abi.decodedLog(inputs, hexString, topics);
    console.log('Decoded log for ReceiveXChainDepositReq event: ', JSON.stringify(decodedLog));

    // Upon receipt, check to see balance of USD, ensure matches the amount sent minus fee
    const busdBal = await busd.balanceOf.call(zcx.address);
    console.log('BUSD bal after xchain: ', busdBal.toString());
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
exports.mintStablecoin = async (stablecoin, destination, amount) => {
    // // Get stablecoin ERC20 address
    // if (network === 'avaxtest') {
    //     const stablecoinAddress = '0x4A0D1092E9df255cf95D72834Ea9255132782318';
    // } else if (network === 'bnbtest') {
    //     const stablecoinAddress = '0x1010bb1b9dff29e6233e7947e045e0ba58f6e92e';
    // }

    // Mint and send to self
    await stablecoin.mint(destination, amount);
};

