const MockZorroController = artifacts.require('MockZorroController');
const MockLPPool = artifacts.require('MockLPPool');
const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    it('sets time multiplier', async () => {
        // Normal
        await instance.setIsTimeMultiplierActive(true);
        assert.isTrue(await instance.isTimeMultiplierActive.call());
        await instance.setIsTimeMultiplierActive(false);
        assert.isFalse(await instance.isTimeMultiplierActive.call());
        // Only by owner
        try {
            await instance.setIsTimeMultiplierActive(true, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro LP Pool params', async () => {
        // Normal
        const lpPool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const avaxToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroLPPoolParams(lpPool, avaxToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPool.call()), lpPool);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPoolOtherToken.call()), avaxToken);
        // Only by owner
        try {
            await instance.setZorroLPPoolParams(lpPool, avaxToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets uni router', async () => {
        // Normal
        const uniRouter = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUniRouter(uniRouter);
        assert.equal(web3.utils.toChecksumAddress(await instance.uniRouterAddress.call()), uniRouter);
        // Only by owner
        try {
            await instance.setUniRouter(uniRouter, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets USDC to ZOR path', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUSDCToZORPath([USDC, ZOR]);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(0)), USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(1)), ZOR);
        // Only by owner
        try {
            await instance.setUSDCToZORPath([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets USDC to ZOR LP pool token other path', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const zorLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUSDCToZorroLPPoolOtherTokenPath([USDC, zorLPPoolOtherToken]);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(0)), USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(1)), zorLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setUSDCToZorroLPPoolOtherTokenPath([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets price feeds', async () => {
        // Normal
        const priceFeedZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const priceFeedLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setPriceFeeds(priceFeedZOR, priceFeedLPPoolOtherToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.priceFeedZOR.call()), priceFeedZOR);
        assert.equal(web3.utils.toChecksumAddress(await instance.priceFeedLPPoolOtherToken.call()), priceFeedLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setPriceFeeds(priceFeedZOR, priceFeedLPPoolOtherToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro X chain endpoint', async () => {
        // Normal
        const contract = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroXChainEndpoint(contract);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroXChainEndpoint.call()), contract);
        // Only by owner
        try {
            await instance.setZorroXChainEndpoint(contract, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('gets the correct time multiplier value', async () => {
        // Set time multiplier active
        await instance.setIsTimeMultiplierActive(true);
        // Prep 
        const durationCommittedWeeks = 5;

        // Assert 
        const multiplierFactor = await instance.getTimeMultiplier.call(durationCommittedWeeks);
        const expectedMultFactor = (1 + 0.2 * Math.sqrt(durationCommittedWeeks))*(1e12);
        assert.closeTo(multiplierFactor/1e12, expectedMultFactor/1e12, 0.01);
    });
});

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    it('gets the correct time multiplier value when time multiplier inactive', async () => {
        // Set time multiplier active
        await instance.setIsTimeMultiplierActive(false);

        // Prep 
        const durationCommittedWeeks = 5;

        // Assert 
        const multiplierFactor = await instance.getTimeMultiplier.call(durationCommittedWeeks);
        const expectedMultFactor = 1e12;
        assert.equal(multiplierFactor, expectedMultFactor);
    });
});

contract('ZorroControllerInvestment Main', async accounts => {
    let instance, lpPool, vault;

    before(async () => {
        // Get contracts
        instance = await MockZorroController.deployed();
        lpPool = await MockLPPool.deployed();
        vault = await MockVaultStandardAMM.deployed();

        // Create pool
        await instance.add(
            1,
            lpPool.address,
            true,
            vault.address
        );
    });

    it('deposits Want token with local account', async () => {
        // Prep
        const pid = 0;
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.035', 'ether'));
        const weeksCommitted = 4; 

        // Mint want tokens to account
        await lpPool.mint(accounts[0], wantAmt);
        // Approve
        await lpPool.approve(instance.address, wantAmt);

        // Run
        await instance.deposit(pid, wantAmt, weeksCommitted);

        // Test

        // TODO

        // Updates Pool rewards

        // Performs Vault deposit

        // Updates poolInfo

        // Updates trancheInfo ledger

    });

    // TODO: How to test for case with foreign account

    xit('deposits USDC into Vault', async () => {

    });

    xit('withdraws Want token', async () => {

    });

    xit('withdraws from Vault into USDC', async () => {

    });

    xit('gets pending rewards by tranche', async () => {

    });

    xit('transfers investment', async () => {

    });

    xit('withdraws all tranches owned by a user in a pool', async () => {

    });
});