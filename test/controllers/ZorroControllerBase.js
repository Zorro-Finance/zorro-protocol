const MockZorroController = artifacts.require('MockZorroController');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    it('sets key addresses', async () => {
        // Normal
        const mockZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const mockUSDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setKeyAddresses(
            mockZOR,
            mockUSDC
        );

        const newZOR = web3.utils.toChecksumAddress(await instance.ZORRO.call());
        const newUSDC = web3.utils.toChecksumAddress(await instance.defaultStablecoin.call());

        assert.equal(newZOR, mockZOR);
        assert.equal(newUSDC, mockUSDC);

        // Only by owner
        try {
            await instance.setKeyAddresses(mockZOR, mockUSDC, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets key contracts', async () => {
        // Normal
        const mockPublicPool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const mockZorVault = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroContracts(mockPublicPool, mockZorVault);

        const newPublicPool = web3.utils.toChecksumAddress(await instance.publicPool.call());
        const newZorVault = web3.utils.toChecksumAddress(await instance.zorroStakingVault.call());

        assert.equal(newPublicPool, mockPublicPool);
        assert.equal(newZorVault, mockZorVault);

        // Only by owner
        try {
            await instance.setZorroContracts(mockPublicPool, mockZorVault, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets start block', async () => {
        // Normal
        const mockStartBlock = 543210;
        await instance.setStartBlock(mockStartBlock);
        assert.equal(await instance.startBlock.call(), mockStartBlock);

        // Immutable 
        try {
            await instance.setStartBlock(mockStartBlock + 1);
        } catch (err) {
            assert.include(err.message, 'blockParams immutable');
        }

        // Only by owner
        try {
            await instance.setStartBlock(mockStartBlock + 1, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets rewards params', async () => {
        // Normal
        const blocksPerDay = 50000;
        const distFactorMin = 8;
        const distFactorMax = 31;
        const baseRewardRate = 10;
        const chainMultiplier = 27;

        await instance.setRewardParams(
            blocksPerDay,
            [distFactorMin, distFactorMax],
            baseRewardRate,
            chainMultiplier
        );

        assert.equal(await instance.blocksPerDay.call(), blocksPerDay);
        assert.equal(await instance.ZORRODailyDistributionFactorBasisPointsMin.call(), distFactorMin);
        assert.equal(await instance.ZORRODailyDistributionFactorBasisPointsMax.call(), distFactorMax);
        assert.equal(await instance.baseRewardRateBasisPoints.call(), baseRewardRate);
        assert.equal(await instance.chainMultiplier.call(), chainMultiplier);

        // Only by owner
        try {
            await instance.setRewardParams(
                0,
                [],
                0,
                0,
                { from: accounts[1] }
            );
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets target TVL capture', async () => {
        // Normal 
        const tvlCapture = 200;

        await instance.setTargetTVLCaptureBAsisPoints(tvlCapture);

        assert.equal(await instance.targetTVLCaptureBasisPoints.call(), tvlCapture);

        // Only by owner
        try {
            await instance.setTargetTVLCaptureBAsisPoints(tvlCapture);
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }

        // Only home chain
        await instance.setXChainParams(2, 0, web3.utils.randomHex(20));
        try {
            await instance.setTargetTVLCaptureBAsisPoints(tvlCapture + 1, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'only home chain');
        }
        // Reset
        // TODO: For all these reset sections, just wrap into a new contract() function so you get a new deployment
        await instance.setXChainParams(0, 0, web3.utils.randomHex(20));
    });

    it('sets cross chain params', async () => {
        // Normal 
        const homeChainController = web3.utils.randomHex(20);
        const chainId = 1;
        const homeChainId = 2;
        await instance.setXChainParams(chainId, homeChainId, homeChainController);

        // Reset 
        await instance.setXChainParams(0, 0, homeChainController);

        // Only by owner
        try {
            await instance.setXChainParams(0, 0, homeChainController, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro controller Oracle', async () => {
        // Normal
        const oracle = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroControllerOracle(oracle);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroControllerOracle).call(), oracle);

        // Only by owner
        try {
            await instance.setZorroControllerOracle(oracle, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro per block', async () => {
        // Only by Zorro Controller oracle
        try {
            await instance.setZorroPerBlock(
                totalChainMultips,
                totalMarketTVL,
                targetTVLCapture,
                totalZORTVL,
                publicPoolBal
            );
        } catch (err) {
            assert.include(err.message, 'only Zorro oracle');
        }

        // Normal 
        await instance.setZorroControllerOracle(accounts[0]);
        const chainMultiplier = 1;
        const totalChainMultips = 1000;
        const totalMarketTVL = 100e9;
        const targetTVLCapture = 200;
        const totalZORTVL = 1e9;
        const publicPoolBal = web3.utils.toWei('700000', 'ether');
        const baseRewardRate = 10;
        const distFactorMin = 1;
        const distFactorMax = 20;
        const blocksPerDay = 28800;
        await instance.setRewardParams(
            blocksPerDay,
            [distFactorMin, distFactorMax],
            chainMultiplier,
            baseRewardRate
        );
        let expZORROPerBlock;
        let dailyDistBP;

        // Variation: mid range
        await instance.setZorroPerBlock(
            totalChainMultips,
            totalMarketTVL,
            targetTVLCapture,
            totalZORTVL,
            publicPoolBal
        );

        dailyDistBP = baseRewardRate * totalMarketTVL * targetTVLCapture / (10000 * totalZORTVL);
        expZORROPerBlock = (dailyDistBP * publicPoolBal / 10000) * (chainMultiplier / totalChainMultips) * (1 / blocksPerDay);

        assert.equal(await instance.ZORROPerBlock.call(), expZORROPerBlock);

        // Variation: low rail (Rm < 0.01 %)
        await instance.setZorroPerBlock(
            totalChainMultips,
            100e9, // totalMarketTVL,
            5, // targetTVLCapture,
            1e9, // totalZORTVL,
            publicPoolBal
        );

        dailyDistBP = distFactorMin;
        expZORROPerBlock = (dailyDistBP * publicPoolBal / 10000) * (chainMultiplier / totalChainMultips) * (1 / blocksPerDay);

        assert.equal(await instance.ZORROPerBlock.call(), expZORROPerBlock);

        // Variation: high rail (Rm > 0.2 %)
        await instance.setZorroPerBlock(
            totalChainMultips,
            100e9, // totalMarketTVL,
            300, // targetTVLCapture,
            1e9, // totalZORTVL,
            publicPoolBal
        );

        dailyDistBP = distFactorMax;
        expZORROPerBlock = (dailyDistBP * publicPoolBal / 10000) * (chainMultiplier / totalChainMultips) * (1 / blocksPerDay);

        assert.equal(await instance.ZORROPerBlock.call(), expZORROPerBlock);
    });

    xit('updates pool rewards', async () => {

    });

    xit('does not update pool if no elapsed blocks', async () => {

    });

    xit('updates pool rewards for xchain', async () => {

    });

    xit('transfers stuck tokens', async () => {
        // Only by owner

        // Only for NON Zorro tokens
    });
})