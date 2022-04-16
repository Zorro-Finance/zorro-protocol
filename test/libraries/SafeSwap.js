const MockSafeSwapUni = artifacts.require('MockSafeSwapUni');
const MockIAMMRouter02 = artifacts.require("MockIAMMRouter02");
const MockSafeSwapBalancer = artifacts.require('MockSafeSwapBalancer');
const MockIBalancerVault = artifacts.require("MockIBalancerVault");

contract('SafeSwapUni', async accounts => {
    it('calculates correct amount out', async () => {
        // Get contract that wraps lib
        const lib = await MockSafeSwapUni.deployed();
        // Create a mock router
        const router = await MockIAMMRouter02.deployed();
        // Prep test conditions
        const amountIn = 100;
        const priceTokenIn = 342e12;
        const priceTokenOut = 1e12;
        const slippageFactor = 990;
        // Run safeSwap()
        const ans = await lib.safeSwap(
            router.address,
            amountIn,
            priceTokenIn,
            priceTokenOut,
            slippageFactor,
            [],
            '0x0000000000000000000000000000000000000000', 
            9999999,
        );
        assert.equal(ans, 1000); // TODO: Change this to a real #
        // TODO: Listen for Swap event and assert it is emitted
    });
});

contract('SafeSwapBalancer', async accounts => {
    it('calculates correct amount out', async () => {
        // Get contract that wraps lib
        const lib = await MockSafeSwapBalancer.deployed();
        // Create a mock router
        const router = await MockIBalancerVault.deployed();
        // Prep test conditions
        const amountIn = 100;
        const priceTokenIn = 342e12;
        const priceTokenOut = 1e12;
        const slippageFactor = 990;
        // Run safeSwap()
        const ans = await lib.safeSwap(
            router.address,
            '00000000000000000000000000000000',
            {
                amountIn: 10000,
                priceToken0: 3.0188e12,
                priceToken1: 1e12,
                token0: '0x0000000000000000000000000000000000000000',
                token1: '0x0000000000000000000000000000000000000000',
                token0Weight: 5000,
                token1Weight: 5000,
                maxMarketMovementAllowed: 990,
                path: [],
                destination: lib.address
            }
        );
        assert.equal(ans, 1000); // TODO: Change this to a real #
        // TODO: Listen for Swap event and assert it is emitted
    });
});