const MockVaultZorro = artifacts.require('MockVaultZorro');
const zeroAddress = '0x0000000000000000000000000000000000000000';

const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");

const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');
const MockPriceUSDC = artifacts.require('MockPriceUSDC');

const approvalEventSig = web3.eth.abi.encodeEventSignature('Approval(address,address,uint256)');
const swappedEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');

const setupContracts = async (accounts) => {
    // Router
    const router = await MockAMMRouter02.deployed();
    await router.setBurnAddress(accounts[4]);
    // USDC
    const usdc = await MockUSDC.deployed();
    // Tokens
    const ZORToken = await MockZorroToken.deployed();
    // Vault
    const instance = await MockVaultZorro.deployed();
    await instance.setWantAddress(ZORToken.address);
    await instance.setToken0Address(ZORToken.address);
    await instance.setRewardsAddress(accounts[3]);
    await instance.setBurnAddress(accounts[4]);
    await instance.setUniRouterAddress(router.address);
    await instance.setDefaultStablecoin(usdc.address);
    await instance.setZORROAddress(ZORToken.address);
    // Set controller
    await instance.setZorroControllerAddress(accounts[0]);
    // Price feeds
    const token0PriceFeed = await MockPriceAggToken0.deployed();
    const earnTokenPriceFeed = await MockPriceAggEarnToken.deployed();
    const ZORPriceFeed = await MockPriceAggZOR.deployed();
    const lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
    const stablecoinPriceFeed = await MockPriceAggLPOtherToken.deployed();
    await instance.setPriceFeed(0, token0PriceFeed.address);
    await instance.setPriceFeed(2, earnTokenPriceFeed.address);
    await instance.setPriceFeed(3, ZORPriceFeed.address);
    await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed.address);
    await instance.setPriceFeed(5, stablecoinPriceFeed.address);
    // Swap paths
    await instance.setSwapPaths(0, [usdc.address, ZORToken.address]);
    await instance.setSwapPaths(2, [ZORToken.address, usdc.address]);

    return {
        instance,
        router,
        usdc,
        ZORToken,
    };
};

contract('VaultZorro', async accounts => {
    let instance, ZORToken;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        ZORToken = setupObj.ZORToken;
    });
    
    it('deposits want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(0);
        } catch (err) {
            assert.include(err.message, 'Want token deposit must be > 0');
        }

        // Mint some LP tokens for the test
        await ZORToken.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await ZORToken.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

        /* First deposit */
        // Deposit
        const tx = await instance.depositWantToken(wantAmt);

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred) {
                transferred = rl;
            }
        }

        // Assert: transfers Want token
        assert.equal(web3.utils.toChecksumAddress(web3.utils.toHex(web3.utils.toBN(transferred.topics[1]))), accounts[0]);
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));

        // Assert: increments shares (total shares and user shares)
        assert.isTrue((await instance.sharesTotal.call()).eq(wantAmt));

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

    it('withdraws want token', async () => {
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
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            }
        }

        // Assert: Correct sharesTotal
        const sharesRemoved = wantAmt.mul(currentSharesTotal).div(currentWantLockedTotal);
        const expectedSharesTotal = currentSharesTotal.sub(sharesRemoved);
        assert.isTrue((await instance.sharesTotal.call()).eq(expectedSharesTotal));

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

contract('VaultZorro', async accounts => {
    let instance, usdc, ZORToken;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        usdc = setupObj.usdc;
        ZORToken = setupObj.ZORToken;
    });

    it('exchanges USDC for want token', async () => {
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
        const preExchangeWantBal = await ZORToken.balanceOf.call(accounts[0]);
        // Transfer USDC
        await usdc.mint(accounts[0], amountUSD);
        await usdc.transfer(instance.address, amountUSD);
        // Exchange
        const tx = await instance.exchangeUSDForWantToken(amountUSD, 990);

        // Logs
        const { rawLogs } = tx.receipt;

        let swappedTokens = [];
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig) {
                if (web3.utils.toBN(topics[2]).eq(amountUSD)) {
                    swappedTokens.push(rl);
                }
            }
        }

        // Assert: Swap event for token 0.
        assert.equal(swappedTokens.length, 1);

        // Assert: Want token obtained
        const postExchangeWantBal = await ZORToken.balanceOf.call(accounts[0]);
        assert.isTrue(postExchangeWantBal.sub(preExchangeWantBal).eq(amountUSD.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000)))); // Assumes 1:1 exchange rate

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

contract('VaultZorro', async accounts => {
    let instance, usdc, ZORToken;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        usdc = setupObj.usdc;
        ZORToken = setupObj.ZORToken;
    });

    it('exchanges want token for USD', async () => {
        /* Prep */
        // Transfer Want token
        const wantAmt = web3.utils.toBN(web3.utils.toWei('5', 'ether'));
        await ZORToken.mint(accounts[0], wantAmt);
        // Allow vault to spend want token
        await ZORToken.approve(instance.address, wantAmt);

        /* Exchange (0) */
        try {
            await instance.exchangeWantTokenForUSD(0, 990);
        } catch (err) {
            assert.include(err.message, 'negWant');
        }

        /* Exchange (> 0) */

        // Vars
        const USDCPreExch = await usdc.balanceOf.call(accounts[0]);
        const expUSDC = (wantAmt.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000))).add(USDCPreExch); // Assumes 1:1 exch rate, no slippage

        // Exchange
        await instance.exchangeWantTokenForUSD(wantAmt, 990);

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