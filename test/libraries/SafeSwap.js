const MockSafeSwapUni = artifacts.require('MockSafeSwapUni');
const MockIAMMRouter02 = artifacts.require("MockIAMMRouter02");
const MockSafeSwapBalancer = artifacts.require('MockSafeSwapBalancer');
const MockIBalancerVault = artifacts.require("MockIBalancerVault");

contract('SafeSwapUni', async accounts => {
    let router;
    let lib;

    before(async () => {
        // Create a mock router
        router = await MockIAMMRouter02.deployed();

        // Get contract that wraps lib
        lib = await MockSafeSwapUni.deployed();
    });

    it('calculates correct amount out when exchange rates are provided', async () => {
        // Prep test conditions
        const amountIn = 100e18; // Qty 100
        const priceTokenIn = 342e12; // Exchange rate of 342 USD per In token
        const priceTokenOut = 1e12; // Parity with USD
        const slippageFactor = 990;
        // Run safeSwap()
        const tx = await lib.safeSwap(
            router.address,
            web3.utils.toBN(amountIn),
            priceTokenIn,
            priceTokenOut,
            slippageFactor,
            [],
            '0x0000000000000000000000000000000000000000', 
            9999999,
        );
        // Get emitted log results 
        // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
        const {rawLogs} = tx.receipt;
        const {topics} = rawLogs[0];
        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]);

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        assert.equal(
            emittedMinAmtOut, 
            ((amountIn*priceTokenIn) / priceTokenOut) * (slippageFactor/1000) 
        );
    });

    it('calculates correct amount out when exchange rates ommitted', async () => {
        // Prep test conditions
        const amountIn = 100e18; // Qty 100
        // Simulate the case that we do not know the exchange rates
        const priceTokenIn = 0;
        const priceTokenOut = 0;
        const slippageFactor = 990;
        // Run safeSwap()
        const tx = await lib.safeSwap(
            router.address,
            web3.utils.toBN(amountIn),
            priceTokenIn,
            priceTokenOut,
            slippageFactor,
            [],
            '0x0000000000000000000000000000000000000000', 
            9999999,
        );
        // Get emitted log results 
        // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
        const {rawLogs} = tx.receipt;
        const {topics} = rawLogs[0];
        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]);

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        // NOTE: MockIAMMRouter02.getAmountsOut() should just assume amountIN for the sake of testing
        assert.equal(
            emittedMinAmtOut, 
            amountIn * (slippageFactor/1000) 
        );
    });
});

contract('SafeSwapBalancer', async accounts => {
    let vault;
    let lib;

    before(async () => {
        // Create a mock IBalancerVault
        vault = await MockIBalancerVault.deployed();

        // Get contract that wraps lib
        lib = await MockSafeSwapBalancer.deployed();
    });

    it('calculates correct amount out when exchange rates are provided', async () => {
        // Prep test conditions
        const amountIn = 200e18; // 200 tokens
        const priceTokenIn = 342e12; // Price in USD of TokenIN (times 1e12)
        const priceTokenOut = 1e12; // Price in USD of TokenOUT (times 1e12)
        const slippageFactor = 990; // 990 = 1%

        // Run safeSwap()
        const tx = await lib.safeSwap(
            vault.address,
            '0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001',
            {
                amountIn: web3.utils.toHex(200e18),
                priceToken0: priceTokenIn,
                priceToken1: priceTokenOut,
                token0: '0x0000000000000000000000000000000000000000',
                token1: '0x0000000000000000000000000000000000000000',
                token0Weight: 5000,
                token1Weight: 5000,
                maxMarketMovementAllowed: slippageFactor,
                path: [],
                destination: lib.address
            }
        );
        // Get emitted log results 
        const {rawLogs} = tx.receipt;
        const {topics} = rawLogs[0];
        
        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]);

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        assert.equal(
            emittedMinAmtOut, 
            ((amountIn*priceTokenIn) / priceTokenOut) * (slippageFactor/1000) 
        );
    });

    it('calculates correct amount out when exchange rates ommitted', async () => {
        // TODO: Needs to be adapted for the case where exchange rates are ommitted
        // This is just a copy paste from above!!


        // Prep test conditions
        const amountIn = 200e18; // 200 tokens
        const priceTokenIn = 0; // Price in USD of TokenIN (times 1e12)
        const priceTokenOut = 0; // Price in USD of TokenOUT (times 1e12)
        const slippageFactor = 990; // 990 = 1%

        // Run safeSwap()
        const tx = await lib.safeSwap(
            vault.address,
            '0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001',
            {
                amountIn: web3.utils.toHex(200e18),
                priceToken0: priceTokenIn,
                priceToken1: priceTokenOut,
                token0: '0x0000000000000000000000000000000000000000',
                token1: '0x0000000000000000000000000000000000000000',
                token0Weight: 5000,
                token1Weight: 5000,
                maxMarketMovementAllowed: slippageFactor,
                path: [],
                destination: lib.address
            }
        );
        console.log('tx: ', tx);
        // Get emitted log results 
        const {rawLogs} = tx.receipt;
        const {topics} = rawLogs[0];
        console.log('topicsz: ', topics);
        
        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]);

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        assert.equal(
            emittedMinAmtOut, 
            ((amountIn*priceTokenIn) / priceTokenOut) * (slippageFactor/1000) 
        );
    });
});