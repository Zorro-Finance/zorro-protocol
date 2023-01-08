const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');

contract('MockVaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
    });

    it('sets pool ID', async () => {
        // Normal
        const pid = 54;
        await instance.setPid(pid);

        assert.equal(await instance.pid.call(), pid);

        // Only by owner
        try {
            await instance.setPid(0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
    
    it('sets the farm contract address', async () => {
        // Normal
        const farm = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setFarmContractAddress(farm);

        assert.equal(await instance.farmContractAddress.call(), farm);

        // Only by owner
        try {
            await instance.setFarmContractAddress(farm, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets key token addresses', async () => {
        // Normal
        const token0 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token1 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setToken0Address(token0);
        await instance.setToken1Address(token1);

        assert.equal(web3.utils.toChecksumAddress(await instance.token0Address.call()), token0);
        assert.equal(web3.utils.toChecksumAddress(await instance.token1Address.call()), token1);

        // Only by owner
        try {
            await instance.setToken0Address(token0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets earned address', async () => {
        // Normal
        const earned = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setEarnedAddress(earned);

        assert.equal(web3.utils.toChecksumAddress(await instance.earnedAddress.call()), earned);

        // Only by owner
        try {
            await instance.setEarnedAddress(earned, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('set token USDC address', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setDefaultStablecoin(USDC);

        assert.equal(web3.utils.toChecksumAddress(await instance.defaultStablecoin.call()), USDC);

        // Only by owner
        try {
            await instance.setDefaultStablecoin(USDC, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets rewards address', async () => {
        // Normal
        const rewards = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setTreasury(rewards);

        assert.equal(web3.utils.toChecksumAddress(await instance.treasury.call()), rewards);

        // Only by owner
        try {
            await instance.setTreasury(rewards, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets burn address', async () => {
        // Normal
        const burn = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setBurnAddress(burn);

        assert.equal(web3.utils.toChecksumAddress(await instance.burnAddress.call()), burn);

        // Only by owner
        try {
            await instance.setBurnAddress(burn, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets want address', async () => {
        // Normal
        const want = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setWantAddress(want);

        assert.equal(web3.utils.toChecksumAddress(await instance.wantAddress.call()), want);

        // Only by owner
        try {
            await instance.setWantAddress(want, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Uni router address', async () => {
        // Normal
        const uniRouter = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUniRouterAddress(uniRouter);

        assert.equal(web3.utils.toChecksumAddress(await instance.uniRouterAddress.call()), uniRouter);

        // Only by owner
        try {
            await instance.setUniRouterAddress(uniRouter, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets pool address', async () => {
        // Normal
        const pool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setPoolAddress(pool);

        assert.equal(web3.utils.toChecksumAddress(await instance.poolAddress.call()), pool);

        // Only by owner
        try {
            await instance.setPoolAddress(pool, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro LP pool address', async () => {
        // Normal
        const zorroLPPool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroLPPoolAddress(zorroLPPool);
        await instance.setZorroLPPoolOtherToken(otherToken);

        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPool.call()), zorroLPPool);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPoolOtherToken.call()), otherToken);

        // Only by owner
        try {
            await instance.setZorroLPPoolAddress(zorroLPPool, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro controller address', async () => {
        // Normal
        const zc = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroControllerAddress(zc);

        assert.equal(web3.utils.toChecksumAddress(await instance.zorroControllerAddress.call()), zc);

        // Only by owner
        try {
            await instance.setZorroControllerAddress(zc, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro XChain controller address', async () => {
        // Normal
        const zc = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroXChainControllerAddress(zc);

        assert.equal(web3.utils.toChecksumAddress(await instance.zorroXChainController.call()), zc);

        // Only by owner
        try {
            await instance.setZorroXChainControllerAddress(zc, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro single staking vault', async () => {
        // Normal
        const stakingVault = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroStakingVault(stakingVault);

        assert.equal(web3.utils.toChecksumAddress(await instance.zorroStakingVault.call()), stakingVault);

        // Only by owner
        try {
            await instance.setZorroStakingVault(stakingVault, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro token address', async () => {
        // Normal
        const ZORRO = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZORROAddress(ZORRO);

        assert.equal(web3.utils.toChecksumAddress(await instance.ZORROAddress.call()), ZORRO);

        // Only by owner
        try {
            await instance.setZORROAddress(ZORRO, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets price feeds', async () => {
        // Normal
        const token0PriceFeed = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token1PriceFeed = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const earnTokenPriceFeed = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZORPriceFeed = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const lpPoolOtherTokenPriceFeed = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

        await instance.setPriceFeed(0, token0PriceFeed);
        await instance.setPriceFeed(1, token1PriceFeed);
        await instance.setPriceFeed(2, earnTokenPriceFeed);
        await instance.setPriceFeed(3, ZORPriceFeed);
        await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed);

        assert.equal(web3.utils.toChecksumAddress(await instance.token0PriceFeed.call()), token0PriceFeed);
        assert.equal(web3.utils.toChecksumAddress(await instance.token1PriceFeed.call()), token1PriceFeed);
        assert.equal(web3.utils.toChecksumAddress(await instance.earnTokenPriceFeed.call()), earnTokenPriceFeed);
        assert.equal(web3.utils.toChecksumAddress(await instance.ZORPriceFeed.call()), ZORPriceFeed);
        assert.equal(web3.utils.toChecksumAddress(await instance.lpPoolOtherTokenPriceFeed.call()), lpPoolOtherTokenPriceFeed);

        // Only by owner
        try {
            await instance.setPriceFeed(0, token0PriceFeed, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets swap paths', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const AVAX = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token0 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token1 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const earned = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

        let path;

        // stablecoinToToken0Path
        path = [USDC, AVAX, token0];
        await instance.setSwapPaths(0, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.stablecoinToToken0Path.call(i)), path[i]);
        }

        // stablecoinToToken1Path
        path = [USDC, AVAX, token1];
        await instance.setSwapPaths(1, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.stablecoinToToken1Path.call(i)), path[i]);
        }

        // token0ToStablecoinPath
        path = [token0, AVAX, USDC];
        await instance.setSwapPaths(2, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.token0ToStablecoinPath.call(i)), path[i]);
        }

        // token1ToStablecoinPath
        path = [token0, AVAX, USDC];
        await instance.setSwapPaths(3, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.token1ToStablecoinPath.call(i)), path[i]);
        }

        // earnedToToken0Path
        path = [earned, token0];
        await instance.setSwapPaths(4, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.earnedToToken0Path.call(i)), path[i]);
        }

        // earnedToToken1Path
        path = [earned, token1];
        await instance.setSwapPaths(5, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.earnedToToken1Path.call(i)), path[i]);
        }

        // earnedToZORROPath
        path = [earned, ZOR];
        await instance.setSwapPaths(6, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.earnedToZORROPath.call(i)), path[i]);
        }

        // earnedToZORLPPoolOtherTokenPath
        path = [earned, ZOR, otherToken];
        await instance.setSwapPaths(7, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.earnedToZORLPPoolOtherTokenPath.call(i)), path[i]);
        }

        // earnedToStablecoinPath
        path = [earned, USDC];
        await instance.setSwapPaths(8, path);
        for (let i=0; i < path.length; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.earnedToStablecoinPath.call(i)), path[i]);
        }

        // Only by owner
        try {
            await instance.setSwapPaths(0, [], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets fees', async () => {
        const entranceFeeFactor = 9950;
        const withdrawFeeFactor = 9970;
        const controllerFee = 200;
        const buybackRate = 400;
        const revShareRate = 500;

        // Test for green light
        await instance.setFeeSettings(
            entranceFeeFactor,
            withdrawFeeFactor,
            controllerFee,
            buybackRate,
            revShareRate
        );
        assert.equal(await instance.entranceFeeFactor.call(), entranceFeeFactor);
        assert.equal(await instance.withdrawFeeFactor.call(), withdrawFeeFactor);
        assert.equal(await instance.controllerFee.call(), controllerFee);
        assert.equal(await instance.buyBackRate.call(), buybackRate);
        assert.equal(await instance.revShareRate.call(), revShareRate);

        // Test for when exceeding bounds
        try {
            await instance.setFeeSettings(
                8000,
                withdrawFeeFactor,
                controllerFee,
                buybackRate,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_entranceFeeFactor too low');
        }
        try {
            await instance.setFeeSettings(
                11000,
                withdrawFeeFactor,
                controllerFee,
                buybackRate,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_entranceFeeFactor too high');
        }

        try {
            await instance.setFeeSettings(
                entranceFeeFactor,
                880,
                controllerFee,
                buybackRate,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_withdrawFeeFactor too low');
        }

        try {
            await instance.setFeeSettings(
                entranceFeeFactor,
                12000,
                controllerFee,
                buybackRate,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_withdrawFeeFactor too high');
        }

        try {
            await instance.setFeeSettings(
                entranceFeeFactor,
                withdrawFeeFactor,
                2000,
                buybackRate,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_controllerFee too high');
        }

        try {
            await instance.setFeeSettings(
                entranceFeeFactor,
                withdrawFeeFactor,
                controllerFee,
                3000,
                revShareRate
            );
        } catch (err) {
            assert.include(err.message, '_buyBackRate too high');
        }

        try {
            await instance.setFeeSettings(
                entranceFeeFactor,
                withdrawFeeFactor,
                controllerFee,
                buybackRate,
                3000
            );
        } catch (err) {
            assert.include(err.message, '_revShareRate too high');
        }

        // Test for only owner
        try {
            await instance.setFeeSettings(0,0,0,0,0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!gov');
        }
    });

    it('reverses swap paths', async () => {
        const addr0 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const addr1 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

        const res = await instance.reversePath.call([addr0, addr1]);
        assert.equal(web3.utils.toChecksumAddress(res[0]), addr1);
        assert.equal(web3.utils.toChecksumAddress(res[1]), addr0);
    });
});

contract('MockVaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
    });

    it('sets governor props', async () => {
        // Turn on/off gov
        await instance.setOnlyGov(false);
        assert.isFalse(await instance.onlyGov.call());
        await instance.setOnlyGov(true);
        assert.isTrue(await instance.onlyGov.call());

        // Normal
        const gov = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setGov(gov);

        assert.equal(web3.utils.toChecksumAddress(await instance.govAddress.call()), gov);

        // Only by owner
        try {
            await instance.setGov(gov, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!gov');
        }
    });
});