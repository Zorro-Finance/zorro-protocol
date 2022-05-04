const MockSafeSwapUni = artifacts.require('MockSafeSwapUni');
const MockAMMRouter02 = artifacts.require("MockAMMRouter02");
const MockSafeSwapBalancer = artifacts.require('MockSafeSwapBalancer');
const MockBalancerVault = artifacts.require("MockBalancerVault");
const MockAMMToken0 = artifacts.require('MockAMMToken0');
const MockAMMToken1 = artifacts.require('MockAMMToken1');

contract('SafeSwapUni', async accounts => {
    let router, lib, token0, token1;

    before(async () => {
        // Create a mock router
        router = await MockAMMRouter02.deployed();
        await router.setBurnAddress(accounts[4]);

        // Tokens
        token0 = await MockAMMToken0.deployed();
        token1 = await MockAMMToken1.deployed();

        // Get contract that wraps lib
        lib = await MockSafeSwapUni.deployed();
    });

    it('calculates correct amount out when exchange rates are provided', async () => {
        // Prep test conditions
        const amountIn = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const priceTokenIn = 342e12; // Exchange rate of 342 USD per In token
        const priceTokenOut = 1e12; // Parity with USD
        const slippageFactor = 990;
        await token0.mint(lib.address, amountIn);
        await token0.approve(router.address, amountIn);
        // Run safeSwap()
        console.log('router: ', router.address, 
            'acc0: ', accounts[0], 'token0 addr', token0.address);
        const tx = await lib.safeSwap(
            router.address,
            amountIn,
            priceTokenIn,
            priceTokenOut,
            slippageFactor,
            [token0.address, token1.address],
            accounts[1],
            9999999,
        );
        // Get emitted log results 
        // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
        const sig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
        const { rawLogs } = tx.receipt;
        let swapEvent;
        for (let rl of rawLogs) {
            if (rl.topics[0] === sig) {
                swapEvent = rl;
                break;
            }
        }
        const emittedAmtIn = web3.utils.toBN(swapEvent.topics[2]);
        const emittedMinAmtOut = web3.utils.toBN(swapEvent.topics[3]);

        // Check that the amount IN never changed
        console.log('emittedAmtIn: ', emittedAmtIn.toString());
        console.log('actualAmtIn: ', amountIn.toString());
        console.log('emittedMinAmtOut: ', emittedMinAmtOut.toString());
        console.log('priceTokenIn: ', priceTokenIn.toString());
        console.log('priceTokenOut: ', priceTokenOut.toString());
        assert.isTrue(emittedAmtIn.eq(amountIn));
        // Check that the amount out was calculated correctly
        assert.isTrue(
            emittedMinAmtOut.eq(
                amountIn
                    .mul(web3.utils.toBN(priceTokenIn))
                    .mul(web3.utils.toBN(slippageFactor))
                    .div(web3.utils.toBN(priceTokenOut).mul(web3.utils.toBN(1000)))
            )
        );
    });

    it('calculates correct amount out when exchange rates ommitted', async () => {
        // Prep test conditions
        const amountIn = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        // Simulate the case that we do not know the exchange rates
        const priceTokenIn = 0;
        const priceTokenOut = 0;
        const slippageFactor = 990;
        await token0.mint(lib.address, amountIn);
        await token0.approve(router.address, amountIn);
        // Run safeSwap()
        const tx = await lib.safeSwap(
            router.address,
            amountIn,
            priceTokenIn,
            priceTokenOut,
            slippageFactor,
            [token0.address, token1.address],
            accounts[1],
            9999999,
        );
        // Get emitted log results 
        // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
        const sig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
        const { rawLogs } = tx.receipt;
        let swapEvent;
        for (let rl of rawLogs) {
            if (rl.topics[0] === sig) {
                swapEvent = rl;
                break;
            }
        }
        const emittedAmtIn = web3.utils.toBN(swapEvent.topics[2]);
        const emittedMinAmtOut = web3.utils.toBN(swapEvent.topics[3]);

        // Check that the amount IN never changed
        console.log('emittedAmtIn1: ', emittedAmtIn.toString());
        console.log('actualAmtIn1: ', amountIn.toString());
        assert.isTrue(emittedAmtIn.eq(amountIn));
        // Check that the amount out was calculated correctly
        // NOTE: MockAMMRouter02.getAmountsOut() should just assume amountIN for the sake of testing
        assert.isTrue(
            emittedMinAmtOut.eq(
                amountIn
                    .mul(web3.utils.toBN(slippageFactor))
                    .div(web3.utils.toBN(1000))
            )
        );
    });
});

contract('SafeSwapBalancer', async accounts => {
    let vault;
    let lib;

    before(async () => {
        // Create a mock IBalancerVault
        vault = await MockBalancerVault.deployed();

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
        const { rawLogs } = tx.receipt;
        const { topics } = rawLogs[0];

        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]);

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        assert.equal(
            emittedMinAmtOut,
            ((amountIn * priceTokenIn) / priceTokenOut) * (slippageFactor / 1000)
        );
    });

    it('calculates correct amount out when exchange rates ommitted', async () => {
        // Prep test conditions for swapping ACS to BUSD
        const amountIn = 200e18; // 200 tokens
        const priceTokenIn = 0; // Price in USD of TokenIN (times 1e12)
        const priceTokenOut = 0; // Price in USD of TokenOUT (times 1e12)
        const slippageFactor = 990; // 990 = 1%
        const token0 = '0x0000000000000000000000000000000000000000'; // ACS
        const token1 = '0x0000000000000000000000000000000000000001'; // BUSD
        const balTokenIn = 41385; // ACS
        const balTokenOut = 47794; // BUSD
        const token0Weight = 3000; // ACS weight (30%)
        const token1Weight = 1000; // BUSD weight (10%)

        // Prep Balancer vault 
        await vault.setCash(token0, web3.utils.toHex(balTokenIn));
        await vault.setCash(token1, web3.utils.toHex(balTokenOut));

        // Run safeSwap()
        const tx = await lib.safeSwap(
            vault.address,
            '0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001',
            {
                amountIn: web3.utils.toHex(amountIn),
                priceToken0: priceTokenIn,
                priceToken1: priceTokenOut,
                token0,
                token1,
                token0Weight, // Weight for ACS
                token1Weight, // Weight for BUSD
                maxMarketMovementAllowed: slippageFactor,
                path: [],
                destination: lib.address
            }
        );
        console.log('tx: ', tx);
        // Get emitted log results 
        const { rawLogs } = tx.receipt;
        const { topics } = rawLogs[0];

        const emittedAmtIn = web3.utils.toBN(topics[1]);
        const emittedMinAmtOut = web3.utils.toBN(topics[2]).div(web3.utils.toBN(1e12));

        // Check that the amount IN never changed
        assert.equal(emittedAmtIn, amountIn);
        // Check that the amount out was calculated correctly
        const expectedMinOutAmt = web3.utils.toBN((amountIn * (balTokenOut / token1Weight) * (slippageFactor / 1000)) / (balTokenIn / token0Weight)).div(web3.utils.toBN(1e12));
        assert.equal(
            emittedMinAmtOut.toNumber(),
            expectedMinOutAmt.toNumber(),
        );
    });
});