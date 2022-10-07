const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');
const MockAMMFarm = artifacts.require('MockAMMFarm');
const MockVaultZorro = artifacts.require("MockVaultZorro");
const zeroAddress = '0x0000000000000000000000000000000000000000';
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
const MockAMMToken0 = artifacts.require('MockAMMToken0');
const MockAMMToken1 = artifacts.require('MockAMMToken1');
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggToken1 = artifacts.require('MockPriceAggToken1');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');
const MockPriceUSDC = artifacts.require('MockPriceUSDC');
const MockLPPool = artifacts.require('MockLPPool');

const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(uint256,uint256)');
const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
const approvalEventSig = web3.eth.abi.encodeEventSignature('Approval(address,address,uint256)');
const swappedEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const addedLiqEventSig = web3.eth.abi.encodeEventSignature('AddedLiquidity(uint256,uint256,uint256)');
const removedLiqEventSig = web3.eth.abi.encodeEventSignature('RemovedLiquidity(uint256,uint256)');
const buybackEventSig = web3.eth.abi.encodeEventSignature('Buyback(uint256)');
const revShareEventSig = web3.eth.abi.encodeEventSignature('RevShare(uint256)');

const setupContracts = async (accounts) => {
    // Router
    const router = await MockAMMRouter02.deployed();
    await router.setBurnAddress(accounts[4]);
    // USDC
    const usdc = await MockUSDC.deployed();
    // Tokens
    const token0 = await MockAMMToken0.deployed();
    const token1 = await MockAMMToken1.deployed();
    const ZORToken = await MockZorroToken.deployed();
    const ZORLPPoolOtherToken = await MockAMMOtherLPToken.deployed();
    // LP Pool
    const lpPool = await MockLPPool.deployed();
    // Farm contract
    const farmContract = await MockAMMFarm.deployed();
    await farmContract.setWantAddress(lpPool.address);
    await farmContract.setBurnAddress(accounts[4]);
    // Vault
    const zorroStakingVault = await MockVaultZorro.deployed();
    const instance = await MockVaultStandardAMM.deployed();
    await instance.setWantAddress(lpPool.address);
    await instance.setPoolAddress(lpPool.address);
    await instance.setFarmContractAddress(farmContract.address);
    await instance.setZorroStakingVault(zorroStakingVault.address);
    await instance.setEarnedAddress(farmContract.address);
    await instance.setRewardsAddress(accounts[3]);
    await instance.setBurnAddress(accounts[4]);
    await instance.setUniRouterAddress(router.address);
    await instance.setToken0Address(token0.address);
    await instance.setToken1Address(token1.address);
    await instance.setDefaultStablecoin(usdc.address);
    await instance.setZORROAddress(ZORToken.address);
    await instance.setZorroLPPoolOtherToken(ZORLPPoolOtherToken.address);
    // Set controller
    await instance.setZorroControllerAddress(accounts[0]);
    // Price feeds
    const token0PriceFeed = await MockPriceAggToken0.deployed();
    const token1PriceFeed = await MockPriceAggToken1.deployed();
    const earnTokenPriceFeed = await MockPriceAggEarnToken.deployed();
    const ZORPriceFeed = await MockPriceAggZOR.deployed();
    const lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
    const stablecoinPriceFeed = await MockPriceAggLPOtherToken.deployed();
    await instance.setPriceFeed(0, token0PriceFeed.address);
    await instance.setPriceFeed(1, token1PriceFeed.address);
    await instance.setPriceFeed(2, earnTokenPriceFeed.address);
    await instance.setPriceFeed(3, ZORPriceFeed.address);
    await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed.address);
    await instance.setPriceFeed(5, stablecoinPriceFeed.address);
    // Swap paths
    await instance.setSwapPaths(0, [usdc.address, token0.address]);
    await instance.setSwapPaths(1, [usdc.address, token1.address]);
    await instance.setSwapPaths(2, [token0.address, usdc.address]);
    await instance.setSwapPaths(3, [token1.address, usdc.address]);
    await instance.setSwapPaths(4, [farmContract.address, token0.address]);
    await instance.setSwapPaths(5, [farmContract.address, token1.address]);
    await instance.setSwapPaths(6, [farmContract.address, ZORToken.address]);
    await instance.setSwapPaths(7, [farmContract.address, ZORLPPoolOtherToken.address]);
    await instance.setSwapPaths(8, [farmContract.address, usdc.address]);

    return {
        instance,
        router,
        farmContract,
        usdc,
        token0,
        token1,
        ZORToken,
        zorroStakingVault,
        lpPool,
    };
}

contract('VaultStandardAMM', async accounts => {
    let instance, router, lpPool;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
        lpPool = setupObj.lpPool;
    });

    it('deposits Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(0);
        } catch (err) {
            assert.include(err.message, 'want<0');
        }

        // Mint some tokens
        await lpPool.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await lpPool.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

        /* First deposit */
        // Deposit
        const tx = await instance.depositWantToken(wantAmt);

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred;
        let farmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred) {
                transferred = rl;
            } else if (topics[0] === depositedEventSig) {
                farmed = rl;
            }
        }

        // Assert: transfers Want token
        assert.equal(web3.utils.toChecksumAddress(web3.utils.toHex(web3.utils.toBN(transferred.topics[1]))), accounts[0]);
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));

        // Assert: increments shares (total shares and user shares)
        assert.isTrue((await instance.sharesTotal.call()).eq(wantAmt));

        // Assert: calls farm()
        assert.isNotNull(farmed);

        /* Next deposit */
        // Set fees
        await instance.setFeeSettings(
            9990, // 0.1% deposit fee
            10000,
            0,
            0,
            0
        );
        // Deposit
        await instance.depositWantToken(wantAmt);

        // Assert: returns correct shares added (based on current shares etc.)
        const sharesTotal = wantAmt; // Total shares before second deposit
        const wantLockedTotal = wantAmt; // Total want locked before second deposit
        const sharesAdded = wantAmt.mul(sharesTotal).mul(web3.utils.toBN(9990)).div(wantLockedTotal.mul(web3.utils.toBN(10000)));
        const newTotalShares = web3.utils.toBN(sharesAdded).add(wantAmt);
        assert.isTrue((await instance.sharesTotal.call()).eq(newTotalShares));

        /* Only Zorro controller */
        try {
            await instance.depositWantToken(0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });

    it('withdraws Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentWantLockedTotal = await instance.wantLockedTotal.call();

        /* Withdraw 0 */
        try {
           await instance.withdrawWantToken(0); 
        } catch (err) {
            assert.include(err.message, 'negWant');
        }
        
        /* Withdraw > 0 */
        
        // Withdraw
        const tx = await instance.withdrawWantToken(wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        let transferred;
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            } else if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: Correct sharesTotal
        const sharesRemoved = wantAmt.mul(currentSharesTotal).div(currentWantLockedTotal);
        const expectedSharesTotal = currentSharesTotal.sub(sharesRemoved);
        assert.isTrue((await instance.sharesTotal.call()).eq(expectedSharesTotal));

        // Assert: calls unfarm()
        assert.isNotNull(unfarmed);

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));
    });

    it('withdraws safely when excess Want token specified', async () => {
        // Prep
        const currentWantLockedTotal = await instance.wantLockedTotal.call();
        const wantAmt = currentWantLockedTotal.add(web3.utils.toBN(1e12)); // Set to exceed the tokens locked, intentionally

        /* Withdraw > wantToken */

        // Withdraw
        const tx = await instance.withdrawWantToken(wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        let transferred;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            }
        }

        // Assert: Correct sharesTotal
        assert.isTrue((await instance.sharesTotal.call()).isZero());

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(currentWantLockedTotal));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router, usdc;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
        usdc = setupObj.usdc;
    });

    it('exchanges USD for Want token', async () => {
        /* Prep */
        const amountUSD = web3.utils.toBN(web3.utils.toWei('100', 'ether'));

        /* Exchange (0) */
        try {
            await instance.exchangeUSDForWantToken(0, 990);
        } catch (err) {
            assert.include(err.message, 'dep<=0');
        }

        /* Exchange (> balance) */
        try {
            await instance.exchangeUSDForWantToken(amountUSD, 990);
        } catch (err) {
            assert.include(err.message, 'amt>bal');
        }

        /* Exchange (> 0) */
        // Record Want bal pre exchange
        const preExchangeWantBal = await router.balanceOf.call(accounts[0]);
        // Transfer USDC
        await usdc.mint(accounts[0], amountUSD);
        await usdc.transfer(instance.address, amountUSD);
        // Exchange
        const tx = await instance.exchangeUSDForWantToken(amountUSD, 990);

        // Logs
        const { rawLogs } = tx.receipt;

        let swappedTokens = [];
        let addedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig) {
                if (web3.utils.toBN(topics[2]).eq(amountUSD.div(web3.utils.toBN(2)))) {
                    swappedTokens.push(rl);
                }
            } else if (topics[0] === addedLiqEventSig) {
                addedLiq = rl;
            }
        }

        // Assert: Swap event for tokens 0 and 1
        assert.equal(swappedTokens.length, 2);
        
        // Assert: Liquidity added
        assert.isNotNull(addedLiq);


        // Assert: Want token obtained
        const postExchangeWantBal = await router.balanceOf.call(accounts[0]);
        const expLiquidity = web3.utils.toBN(web3.utils.toWei('1', 'ether'));
        assert.isTrue(postExchangeWantBal.sub(preExchangeWantBal).eq(expLiquidity))

        /* Only Zorro Controller */
        try {
            await usdc.mint(accounts[0], amountUSD);
            await usdc.transfer(instance.address, amountUSD);
            await instance.exchangeUSDForWantToken(amountUSD, 990);
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router, usdc, lpPool, token0, token1;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
        usdc = setupObj.usdc;
        lpPool = setupObj.lpPool;
        token0 = setupObj.token0;
        token1 = setupObj.token1;
    });

    it('exchanges Want token for USD', async () => {
        /* Prep */
        // Transfer Want token
        const wantAmt = web3.utils.toBN(web3.utils.toWei('5', 'ether'));
        await lpPool.mint(accounts[0], wantAmt);
        // Give perms
        await lpPool.approve(instance.address, wantAmt);
        await router.setPoolAddress(lpPool.address);
        // Simulate bal & total supply of tokens 0, 1 in pool
        const token0Amt = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const token1Amt = web3.utils.toBN(web3.utils.toWei('3', 'ether'));
        await token0.mint(lpPool.address, token0Amt);
        await token1.mint(lpPool.address, token1Amt);

        /* Exchange (0) */
        try {
            await instance.exchangeWantTokenForUSD(0, 990);
        } catch (err) {
            assert.include(err.message, 'negWant');
        }

        /* Exchange (> 0) */

        // Vars
        const USDCPreExch = await usdc.balanceOf.call(accounts[0]);
        const expToken0 = token0Amt.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000)); // Assumes total supply of LP and amount LP token are the same
        const expToken1 = token1Amt.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000)); // Ditto
        const expUSDC = (expToken0.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000))).add(expToken1.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000))).add(USDCPreExch); // Assumes 1:1 exch rate

        // Exchange
        const tx = await instance.exchangeWantTokenForUSD(wantAmt, 990);

        // Logs
        const { rawLogs } = tx.receipt;

        let removedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === removedLiqEventSig) {
                removedLiq = rl;
            }
        }

        // Assert: Liquidity removed  (event: RemovedLiquidity for tokens 0, 1, no more Want bal)
        assert.isNotNull(removedLiq);

        // Assert: USDC obtained (check Bal)
        assert.isTrue((await usdc.balanceOf.call(accounts[0])).eq(expUSDC));

        /* Only Zorro Controller */
        try {
            await instance.exchangeWantTokenForUSD(wantAmt, 990, {from: accounts[2]});
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, farmContract;

    before(async () => {
        // Setup
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        farmContract = setupObj.farmContract;
        // Fees
        await instance.setFeeSettings(10000, 10000, 500, 600, 300);
    });

    it('auto compounds and earns', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('3', 'ether'));
        // Mint some Earn token to this contract
        await farmContract.mint(instance.address, earnedAmt);

        /* Expectations */
        const controllerFeeAmt = earnedAmt.mul(web3.utils.toBN(500)).div(web3.utils.toBN(10000));
        const buybackAmt = earnedAmt.mul(web3.utils.toBN(600)).div(web3.utils.toBN(10000));
        const revShareAmt = earnedAmt.mul(web3.utils.toBN(300)).div(web3.utils.toBN(10000));
        const token0Amt = (earnedAmt.sub(controllerFeeAmt).sub(buybackAmt).sub(revShareAmt)).div(web3.utils.toBN(2));
        const token1Amt = token0Amt; // Assumes 1:1 exchange rate between Earn, Token0, Token1
        const farmedAmt = web3.utils.toBN(web3.utils.toWei('1', 'ether')); // Default amt returned from Mock addLiquidity

        /* Earn */
        // Earn
        const tx = await instance.earn(990);

        // Logs
        const { rawLogs } = tx.receipt;

        let harvestedEarned, distributedFees, boughtBack, revShared
        let swapped = []; 
        let addedLiq, farmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === withdrewEventSig) {
                harvestedEarned = rl;
            } else if (topics[0] === transferredEventSig && web3.utils.toBN(rl.data).eq(controllerFeeAmt)) {
                distributedFees = rl;
            } else if (topics[0] === buybackEventSig && web3.utils.toBN(topics[1]).eq(buybackAmt)) {
                boughtBack = rl;
            } else if (topics[0] === revShareEventSig && web3.utils.toBN(topics[1]).eq(revShareAmt)) {
                revShared = rl;
            } else if (topics[0] === swappedEventSig && web3.utils.toBN(topics[1]).eq(web3.utils.toBN(instance.address)) && web3.utils.toBN(topics[2]).eq(token0Amt)) {
                swapped.push(rl);
            } else if (topics[0] === addedLiqEventSig && web3.utils.toBN(topics[1]).eq(token0Amt) && web3.utils.toBN(topics[2]).eq(token1Amt)) {
                addedLiq = rl;
            } else if (topics[0] === depositedEventSig && web3.utils.toBN(topics[2]).eq(farmedAmt)) {
                farmed = rl;
            }
        }

        // Assert: Harvests Earn token (event Withdrew w/ amount 0)
        assert.isNotNull(harvestedEarned);
        
        // Assert: Distributes fees (event Transfer to account0 w/ controller fee)
        assert.isNotNull(distributedFees);
        
        // Assert: Buys back (event Buyback w/ buyback rate)
        assert.isNotNull(boughtBack);
        
        // Assert: Revshares (event Revshare w/ revshare rate)
        assert.isNotNull(revShared);

        // Assert: swaps tokens 0, 1 (event SwappedToken for tokens 0, 1)
        assert.equal(swapped.length, 2);
        
        // Assert: Adds liquidity (event AddedLiquidity)
        assert.isNotNull(addedLiq);
        
        // Assert: Updates last earn block (block should match latest block)
        assert.isTrue((await instance.lastEarnBlock.call()).eq(web3.utils.toBN(await web3.eth.getBlockNumber())))

        // Assert: Re-Farms want token (event Deposited w/ correct amount)
        assert.isNotNull(farmed);
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        farmContract = setupObj.farmContract;
    });

    it('buys back Earn token, adds liquidity, and burns LP', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const rates = {
            earn: 1.2e12,
            ZOR: 1050*(1e12),
            lpPoolOtherToken: 333*(1e12),
            stablecoin: 1e12,
        };
        const slippage = 990; // 1%
        const expZOR = earnedAmt.mul(web3.utils.toBN(0.5 * rates.ZOR * slippage).div(web3.utils.toBN(1000 * rates.earn)));
        const expLPOther = earnedAmt.mul(web3.utils.toBN(0.5 * rates.lpPoolOtherToken * slippage).div(web3.utils.toBN(1000 * rates.earn)));
        // Send some Earn token
        await farmContract.mint(instance.address, earnedAmt);

        /* Buyback */
        // Buyback
        const tx = await instance.buybackOnChain(earnedAmt, slippage, rates);

        // Logs
        const { rawLogs } = tx.receipt;
        let swapped = [];
        let addedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig && web3.utils.toBN(topics[1]).eq(web3.utils.toBN(instance.address)) && web3.utils.toBN(topics[2]).eq(earnedAmt.div(web3.utils.toBN(2)))) {
                swapped.push(rl);
            } else if (topics[0] === addedLiqEventSig && web3.utils.toBN(topics[1]).eq(expZOR) && web3.utils.toBN(topics[2]).eq(expLPOther)) {
                addedLiq = rl;
            }
        }

        // Assert: Swapped in to ZOR, other token (event: SwappedToken x 2)
        assert.equal(swapped.length, 2);
        // Assert: Added liquidity (event: AddedLiquidity)
        assert.isNotNull(addedLiq);
    });

});

contract('VaultStandardAMM', async accounts => {
    let instance, zorroStakingVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        farmContract = setupObj.farmContract;
        zorroStakingVault = setupObj.zorroStakingVault;
    });

    it('shares revenue with ZOR stakers', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const rates = {
            earn: 1.2e12,
            ZOR: 1050*(1e12),
            lpPoolOtherToken: 333*(1e12),
            stablecoin: 1e12,
        };
        // Send some Earn token
        await farmContract.mint(instance.address, earnedAmt);

        /* RevShare */
        // RevShare
        const tx = await instance.revShareOnChain(earnedAmt, 990, rates);

        // Logs
        const { rawLogs } = tx.receipt;

        let swapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig && web3.utils.toBN(topics[1]).eq(web3.utils.toBN(zorroStakingVault.address) && web3.utils.toBN(topics[2]).eq(earnedAmt)) ) {
                swapped = rl;
            }
        }

        // Assert: Swapped to ZOR
        assert.isNotNull(swapped);
    });

});

contract('VaultStandardAMM', async accounts => {
    let instance, farmContract;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        farmContract = setupObj.farmContract;
    });

    it('swaps Earn token to USD', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const rates = {
            earn: 1.2e12,
            ZOR: 1050,
            lpPoolOtherToken: 333,
            stablecoin: 1e12,
        };
        // Send some Earn token
        await farmContract.mint(instance.address, earnedAmt);

        /* SwapEarnedToUSD */
        // Swap
        const tx = await instance.swapEarnedToUSD(
            earnedAmt,
            accounts[2],
            990,
            rates
        );

        // Logs
        const { rawLogs } = tx.receipt;

        let approvedSpending, swapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === approvalEventSig && !approvalEventSig && topics[2] === router.address && web3.utils.toBN(rl.data).eq(earnedAmt)) {
                approvedSpending = rl;
            } else if (topics[0] === swappedEventSig && topics[1] === accounts[2] && web3.utils.toBN(topics[2]).eq(earnedAmt)) {
                swapped = rl;
            }
        }

        // Assert: Approval
        assert.isNotNull(approvedSpending);
        // Assert: Swap
        assert.isNotNull(swapped);
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, lpPool;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        lpPool = setupObj.lpPool;
    });

    it('farms Want token', async () => {
        // Mint tokens
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.628', 'ether'));
        await lpPool.mint(instance.address, wantAmt);
        // Farm
        const tx = await instance.farm();
        const { rawLogs } = tx.receipt;

        let depositedInFarm;
        let approvedSpending;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === depositedEventSig) {
                depositedInFarm = rl;
            } else if (topics[0] === approvalEventSig && !approvedSpending) {
                approvedSpending = rl;
            }
        }

        // Assert: Increments Want locked total
        assert.isTrue((await instance.wantLockedTotal.call()).eq(wantAmt));

        // Assert: Allows farm contract to spend
        assert.equal(web3.utils.toHex(web3.utils.toBN(approvedSpending.data)), web3.utils.toHex(wantAmt));

        // Assert: farms token (wantLockedTotal incremented, farm's deposit() func called)
        assert.isTrue(web3.utils.toBN(depositedInFarm.topics[2]).eq(wantAmt));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router, lpPool;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
        lpPool = setupObj.lpPool;
    });

    it('unfarms Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(1e17)
        
        // Mint some tokens
        await lpPool.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await lpPool.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());
        // Simulate deposit
        await instance.depositWantToken(wantAmt);
        const wantLockedTotal = await instance.wantLockedTotal.call();

        // Unfarm
        const tx = await instance.unfarm(wantAmt);

        // Get logs
        const { rawLogs } = tx.receipt;
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: called unfarm() func
        assert.isTrue(web3.utils.toBN(unfarmed.topics[1]).eq(await instance.pid.call()));
        assert.isTrue(web3.utils.toBN(unfarmed.topics[2]).eq(wantAmt));
    });
});