// TODO: Run these without Mock tokens

// const MockSafeSwapUni = artifacts.require('MockSafeSwapUni');
// const MockAMMRouter02 = artifacts.require("MockAMMRouter02");
// const MockAMMToken0 = artifacts.require('MockAMMToken0');
// const MockAMMToken1 = artifacts.require('MockAMMToken1');

// const SwappedTokenEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');

// contract('SafeSwapUni', async accounts => {
//     let router, lib, token0, token1;

//     before(async () => {
//         // Create a mock router
//         router = await MockAMMRouter02.deployed();
//         await router.setBurnAddress(accounts[4]);

//         // Tokens
//         token0 = await MockAMMToken0.deployed();
//         token1 = await MockAMMToken1.deployed();

//         // Get contract that wraps lib
//         lib = await MockSafeSwapUni.deployed();
//     });

//     xit('calculates correct amount out when exchange rates are provided', async () => {
//         // Prep test conditions
//         const amountIn = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
//         const priceTokenIn = 342e12; // Exchange rate of 342 USD per In token
//         const priceTokenOut = 1e12; // Parity with USD
//         const slippageFactor = 990;
//         const decimals = [18, 18];
//         await token0.mint(lib.address, amountIn);
//         await token0.approve(router.address, amountIn);
//         // Run safeSwap()
//         const tx = await lib.safeSwap(
//             router.address,
//             amountIn,
//             [priceTokenIn, priceTokenOut],
//             slippageFactor,
//             [token0.address, token1.address],
//             decimals,
//             accounts[1],
//             9999999,
//         );
//         // Get emitted log results 
//         // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
//         const { rawLogs } = tx.receipt;
//         let swapEvent;
//         for (let rl of rawLogs) {
//             if (rl.topics[0] === SwappedTokenEventSig) {
//                 swapEvent = rl;
//                 break;
//             }
//         }
//         const emittedAmtIn = web3.utils.toBN(swapEvent.topics[2]);
//         const emittedMinAmtOut = web3.utils.toBN(swapEvent.topics[3]);

//         // Check that the amount IN never changed
//         assert.isTrue(emittedAmtIn.eq(amountIn));
//         // Check that the amount out was calculated correctly
//         assert.isTrue(
//             emittedMinAmtOut.eq(
//                 amountIn
//                     .mul(web3.utils.toBN(priceTokenIn))
//                     .mul(web3.utils.toBN(slippageFactor))
//                     .div(web3.utils.toBN(priceTokenOut).mul(web3.utils.toBN(1000)))
//             )
//         );
//     });

//     xit('calculates correct amount out when exchange rates ommitted', async () => {
//         // Prep test conditions
//         const amountIn = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
//         // Simulate the case that we do not know the exchange rates
//         const priceTokenIn = 0;
//         const priceTokenOut = 0;
//         const slippageFactor = 990;
//         const decimals = [18, 18];
//         await token0.mint(lib.address, amountIn);
//         await token0.approve(router.address, amountIn);
//         // Run safeSwap()
//         const tx = await lib.safeSwap(
//             router.address,
//             amountIn,
//             [priceTokenIn, priceTokenOut],
//             slippageFactor,
//             [token0.address, token1.address],
//             decimals,
//             accounts[1],
//             9999999,
//         );
//         // Get emitted log results 
//         // (Also: The fact that the SwappedToken event was emitted means that the router swap occured)
//         const { rawLogs } = tx.receipt;
//         let swapEvent;
//         for (let rl of rawLogs) {
//             if (rl.topics[0] === SwappedTokenEventSig) {
//                 swapEvent = rl;
//                 break;
//             }
//         }
//         const emittedAmtIn = web3.utils.toBN(swapEvent.topics[2]);
//         const emittedMinAmtOut = web3.utils.toBN(swapEvent.topics[3]);

//         // Check that the amount IN never changed
//         assert.isTrue(emittedAmtIn.eq(amountIn));
//         // Check that the amount out was calculated correctly
//         // NOTE: MockAMMRouter02.getAmountsOut() should just assume amountIN for the sake of testing
//         assert.isTrue(
//             emittedMinAmtOut.eq(
//                 amountIn
//                     .mul(web3.utils.toBN(slippageFactor))
//                     .div(web3.utils.toBN(1000))
//             )
//         );
//     });
// });