const MockVaultAlpaca = artifacts.require('MockVaultAlpaca');
const zeroAddress = '0x0000000000000000000000000000000000000000';

const MockAlpacaFarm = artifacts.require('MockAlpacaFarm');
const MockAlpacaVault = artifacts.require('MockAlpacaVault');
const MockVaultZorro = artifacts.require("MockVaultZorro");
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockBUSD = artifacts.require('MockBUSD');
const MockAlpaca = artifacts.require('MockAlpaca');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
const MockAMMToken0 = artifacts.require('MockAMMToken0');
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');
const MockPriceBUSD = artifacts.require('MockPriceBUSD');

const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(address,uint256)');
const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(address,uint256)');
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
    // USD
    const busd = await MockBUSD.deployed();
    // Tokens
    const token0 = await MockAMMToken0.deployed();
    const alpaca = await MockAlpaca.deployed();
    const ZORToken = await MockZorroToken.deployed();
    const ZORLPPoolOtherToken = await MockAMMOtherLPToken.deployed();
    // LP
    const alpacaVault = await MockAlpacaVault.deployed();
    await alpacaVault.setToken0Address(token0.address);
    await alpacaVault.setBurnAddress(accounts[4]);
    // Farm contract
    const farmContract = await MockAlpacaFarm.deployed();
    await farmContract.setWantAddress(alpacaVault.address);
    await farmContract.setBurnAddress(accounts[4]);
    // Vault
    const zorroStakingVault = await MockVaultZorro.deployed();
    const instance = await MockVaultAlpaca.deployed();
    await instance.setWantAddress(alpacaVault.address);
    await instance.setPoolAddress(alpacaVault.address); // IAlpacaVault (for entering strategy)
    await instance.setFarmContractAddress(farmContract.address); // IFairLaunch (for farming want token)
    await instance.setZorroStakingVault(zorroStakingVault.address);
    await instance.setEarnedAddress(alpaca.address);
    await instance.setTreasury(accounts[3]);
    await instance.setBurnAddress(accounts[4]);
    await instance.setUniRouterAddress(router.address);
    await instance.setToken0Address(token0.address);
    await instance.setDefaultStablecoin(busd.address);
    await instance.setZORROAddress(ZORToken.address);
    await instance.setZorroLPPoolOtherToken(ZORLPPoolOtherToken.address);
    // Set controller
    await instance.setZorroControllerAddress(accounts[0]);
    // Price feeds
    const token0PriceFeed = await MockPriceAggToken0.deployed();
    const earnTokenPriceFeed = await MockPriceAggEarnToken.deployed();
    const ZORPriceFeed = await MockPriceAggZOR.deployed();
    const lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
    // const stablecoinPriceFeed = await MockPriceAggLPOtherToken.deployed();
    const BUSDPriceFeed = await MockPriceBUSD.deployed();
    await instance.setPriceFeed(0, token0PriceFeed.address);
    await instance.setPriceFeed(2, earnTokenPriceFeed.address);
    await instance.setPriceFeed(3, ZORPriceFeed.address);
    await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed.address);
    await instance.setPriceFeed(5, BUSDPriceFeed.address);
    // Swap paths
    await instance.setSwapPaths(0, [busd.address, token0.address]);
    await instance.setSwapPaths(2, [token0.address, busd.address]);
    await instance.setSwapPaths(4, [alpaca.address, token0.address]);
    await instance.setSwapPaths(6, [alpaca.address, ZORToken.address]);
    await instance.setSwapPaths(7, [alpaca.address, ZORLPPoolOtherToken.address]);
    await instance.setSwapPaths(8, [alpaca.address, busd.address]);
    await instance.setStablecoinSwapPaths(0, [busd.address, token0.address]);
    await instance.setStablecoinSwapPaths(1, [busd.address, ZORToken.address]);
    await instance.setStablecoinSwapPaths(2, [busd.address, ZORLPPoolOtherToken.address]);

    return {
        instance,
        alpacaVault,
        farmContract,
        busd,
        alpaca,
        token0,
        ZORToken,
        zorroStakingVault,
    };
};

contract('VaultAlpaca', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultAlpaca.deployed();
    });

    it('sets BUSD swap paths', async () => {
        // Normal
        const BUSD = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const AVAX = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token0 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        let path;
        // Set stablecoinToToken0Path
        path = [BUSD, AVAX, token0];
        await instance.setStablecoinSwapPaths(0, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.stablecoinToToken0Path.call(i)), path[i]);
        }
        // Set stablecoinToZORROPath
        path = [BUSD, token0, ZOR];
        await instance.setStablecoinSwapPaths(1, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.stablecoinToZORROPath.call(i)), path[i]);
        }
        // Set stablecoinToLPPoolOtherTokenPath
        path = [BUSD, token0, otherToken];
        await instance.setStablecoinSwapPaths(2, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.stablecoinToLPPoolOtherTokenPath.call(i)), path[i]);
        }


        // Only by owner
        try {
            await instance.setStablecoinSwapPaths(0, [], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('VaultAlpaca', async accounts => {
    let instance, alpacaVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpacaVault = setupObj.alpacaVault;
    });

    it('deposits Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(0);
        } catch (err) {
            assert.include(err.message, 'Want token deposit must be > 0');
        }

        // Mint some tokens
        await alpacaVault.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await alpacaVault.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

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

        // Assert: increments shares (total shares)
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

contract('VaultAlpaca', async accounts => {
    let instance, alpacaVault, busd;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpacaVault = setupObj.alpacaVault;
        busd = setupObj.busd;
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
        const preExchangeWantBal = await alpacaVault.balanceOf.call(accounts[0]);
        // Transfer USD
        await busd.mint(accounts[0], amountUSD);
        await busd.transfer(instance.address, amountUSD);
        // Exchange
        const tx = await instance.exchangeUSDForWantToken(amountUSD, 990);

        // Logs
        const { rawLogs } = tx.receipt;

        let swappedTokens = [];
        let addedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig) {
                if (web3.utils.toBN(topics[2]).eq(amountUSD)) {
                    swappedTokens.push(rl);
                }
            } else if (topics[0] === addedLiqEventSig) {
                addedLiq = rl;
            }
        }

        // Assert: Swap event for token 0
        assert.equal(swappedTokens.length, 1);
        
        // Assert: Liquidity added
        assert.isNotNull(addedLiq);


        // Assert: Want token obtained
        const postExchangeWantBal = await alpacaVault.balanceOf.call(accounts[0]);
        const expLiquidity = web3.utils.toBN(web3.utils.toWei('1', 'ether'));
        assert.isTrue(postExchangeWantBal.sub(preExchangeWantBal).eq(expLiquidity))

        /* Only Zorro Controller */
        try {
            await busd.mint(accounts[0], amountUSD);
            await busd.transfer(instance.address, amountUSD);
            await instance.exchangeUSDForWantToken(amountUSD, 990);
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });

});

contract('VaultAlpaca', async accounts => {
    let instance, alpacaVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpacaVault = setupObj.alpacaVault;
    });

    it('farms Want token', async () => {
        // Mint tokens
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.628', 'ether'));
        await alpacaVault.mint(instance.address, wantAmt);
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

contract('VaultAlpaca', async accounts => {
    let instance, alpacaVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpacaVault = setupObj.alpacaVault;
    });

    it('unfarms Earn token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(1e17);
        
        // Mint some tokens
        await alpacaVault.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await alpacaVault.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());
        // Simulate deposit
        await instance.depositWantToken(wantAmt);

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
        assert.isTrue(web3.utils.toBN(unfarmed.topics[2]).eq(wantAmt));
    });

});

contract('VaultAlpaca', async accounts => {
    let instance, alpacaVault, busd;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpacaVault = setupObj.alpacaVault;
        busd = setupObj.busd;
    });

    it('exchanges Want token for USD', async () => {
        /* Prep */
        // Transfer Want token
        const wantAmt = web3.utils.toBN(web3.utils.toWei('5', 'ether'));
        await alpacaVault.mint(accounts[0], wantAmt);
        // Allow VaultAlpaca to spend want token
        await alpacaVault.approve(instance.address, wantAmt);

        /* Exchange (0) */
        try {
            await instance.exchangeWantTokenForUSD(0, 990);
        } catch (err) {
            assert.include(err.message, 'negWant');
        }

        /* Exchange (> 0) */

        // Vars
        const USDPreExch = await busd.balanceOf.call(accounts[0]);
        const expToken0 = web3.utils.toBN(web3.utils.toWei('2', 'ether')); // Hard coded amount in MockVaultAlpaca.sol
        const expUSD = (expToken0.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000))).add(USDPreExch); // Assumes 1:1 exch rate

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

        // Assert: Liquidity removed  (event: RemovedLiquidity for token0, no more Want bal)
        assert.isNotNull(removedLiq);

        // Assert: USD obtained (check Bal)
        assert.isTrue((await busd.balanceOf.call(accounts[0])).eq(expUSD));

        /* Only Zorro Controller */
        try {
            await instance.exchangeWantTokenForUSD(wantAmt, 990, {from: accounts[2]});
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });

});

contract('VaultAlpaca', async accounts => {
    let instance, alpaca;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpaca = setupObj.alpaca;

        // Fees
        await instance.setFeeSettings(
            10000, // Entrance
            10000, // Withdrawal
            300, // Controller
            400, // Buyback
            500, // Revshare
        );
    });

    it('auto compounds and earns', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('3', 'ether'));
        // Mint some Earn token to this contract
        await alpaca.mint(instance.address, earnedAmt);

        /* Expectations */
        const controllerFeeAmt = earnedAmt.mul(web3.utils.toBN(300)).div(web3.utils.toBN(10000));
        const buybackAmt = earnedAmt.mul(web3.utils.toBN(400)).div(web3.utils.toBN(10000));
        const revShareAmt = earnedAmt.mul(web3.utils.toBN(500)).div(web3.utils.toBN(10000));
        const token0Amt = (earnedAmt.sub(controllerFeeAmt).sub(buybackAmt).sub(revShareAmt));
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
        assert.equal(swapped.length, 1);
        
        // Assert: Adds liquidity (event AddedLiquidity)
        assert.isNotNull(addedLiq);
        
        // Assert: Updates last earn block (block should match latest block)
        assert.isTrue((await instance.lastEarnBlock.call()).eq(web3.utils.toBN(await web3.eth.getBlockNumber())))

        // Assert: Re-Farms want token (event Deposited w/ correct amount)
        assert.isNotNull(farmed);
    });

});

contract('VaultAlpaca', async accounts => {
    let instance, alpaca;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpaca = setupObj.alpaca;
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
        await alpaca.mint(instance.address, earnedAmt);

        /* Buyback */
        // Buyback
        const tx = await instance.buybackOnChain(earnedAmt, slippage, rates);

        // Logs
        const { rawLogs } = tx.receipt;
        let swapped = [];
        let addedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig) {
                swapped.push(rl);
            } else if (topics[0] === addedLiqEventSig && web3.utils.toBN(topics[1]).eq(expZOR) && web3.utils.toBN(topics[2]).eq(expLPOther)) {
                addedLiq = rl;
            }
        }

        // Assert: Swapped Earned to BUSD, Swapped in to ZOR, other token (event: SwappedToken x 2)
        assert.equal(swapped.length, 3);
        // Assert: Added liquidity (event: AddedLiquidity)
        assert.isNotNull(addedLiq);
    });

});

contract('VaultAlpaca', async accounts => {
    let instance, alpaca, zorroStakingVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpaca = setupObj.alpaca;
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
        await alpaca.mint(instance.address, earnedAmt);

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

contract('VaultAlpaca', async accounts => {
    let instance, alpaca;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        alpaca = setupObj.alpaca;
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
        await alpaca.mint(instance.address, earnedAmt);

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