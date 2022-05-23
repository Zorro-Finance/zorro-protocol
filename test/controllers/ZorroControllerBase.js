const MockZorroController = artifacts.require('MockZorroController');
const MockZorroToken = artifacts.require('MockZorroToken');
const MockInvestmentVault = artifacts.require('MockInvestmentVault');
const MockLPPool = artifacts.require('MockLPPool');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
        // Set home chain controller address
        await instance.setXChainParams(0, 0, await instance.address);
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

        await instance.setRewardsParams(
            blocksPerDay,
            [distFactorMin, distFactorMax],
            chainMultiplier,
            baseRewardRate
        );

        assert.equal(await instance.blocksPerDay.call(), blocksPerDay);
        assert.equal(await instance.ZORRODailyDistributionFactorBasisPointsMin.call(), distFactorMin);
        assert.equal(await instance.ZORRODailyDistributionFactorBasisPointsMax.call(), distFactorMax);
        assert.equal(await instance.baseRewardRateBasisPoints.call(), baseRewardRate);
        assert.equal(await instance.chainMultiplier.call(), chainMultiplier);

        // Only by owner
        try {
            await instance.setRewardsParams(
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

    it('sets Zorro controller Oracle', async () => {
        // Normal
        const oracle = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroControllerOracle(oracle);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroControllerOracle.call()), oracle);

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
                0,
                0,
                0,
                0,
                0
            );
        } catch (err) {
            assert.include(err.message, 'only Zorro oracle');
        }

        // Normal 
        await instance.setZorroControllerOracle(accounts[0]);
        // Set home chain controller address
        instance.setXChainParams(0, 0, await instance.address);
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
        await instance.setRewardsParams(
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
        expZORROPerBlock = (dailyDistBP * publicPoolBal * chainMultiplier) / (10000 * totalChainMultips * blocksPerDay);

        assert.closeTo((await instance.ZORROPerBlock.call()).toNumber(), expZORROPerBlock, 1);

        // Variation: low rail (Rm < 0.01 %)
        await instance.setZorroPerBlock(
            totalChainMultips,
            100e9, // totalMarketTVL,
            5, // targetTVLCapture,
            1e9, // totalZORTVL,
            publicPoolBal
        );

        dailyDistBP = distFactorMin;
        expZORROPerBlock = (dailyDistBP * publicPoolBal * chainMultiplier) / (10000 * totalChainMultips * blocksPerDay);

        assert.closeTo((await instance.ZORROPerBlock.call()).toNumber(), expZORROPerBlock, 1);

        // Variation: high rail (Rm > 0.2 %)
        await instance.setZorroPerBlock(
            totalChainMultips,
            100e9, // totalMarketTVL,
            300, // targetTVLCapture,
            1e9, // totalZORTVL,
            publicPoolBal
        );

        dailyDistBP = distFactorMax;
        expZORROPerBlock = (dailyDistBP * publicPoolBal * chainMultiplier) / (10000 * totalChainMultips * blocksPerDay);

        assert.closeTo((await instance.ZORROPerBlock.call()).toNumber(), expZORROPerBlock, 1);
    });
});

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });
    
    it('sets target TVL capture', async () => {
        // Normal 
        const tvlCapture = 200;
        
        // Set home chain controller address
        await instance.setXChainParams(0, 0, instance.address);
        // Set capture amount
        await instance.setTargetTVLCaptureBasisPoints(tvlCapture);

        assert.equal(await instance.targetTVLCaptureBasisPoints.call(), tvlCapture);

        // Only by owner
        try {
            await instance.setTargetTVLCaptureBasisPoints(tvlCapture, {from: accounts[1]});
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }

        // Only home chain
        await instance.setXChainParams(2, 0, web3.utils.randomHex(20));
        try {
            await instance.setTargetTVLCaptureBasisPoints(tvlCapture + 1);
        } catch (err) {
            assert.include(err.message, 'only home chain');
        }
    });
});

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    it('sets cross chain params', async () => {
        // Normal 
        const homeChainZorroController = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const chainId = 1;
        const homeChainId = 2;
        await instance.setXChainParams(chainId, homeChainId, homeChainZorroController);
        assert.equal(await instance.chainId.call(), chainId);
        assert.equal(await instance.homeChainId.call(), homeChainId);
        assert.equal(await instance.homeChainZorroController.call(), web3.utils.toChecksumAddress(homeChainZorroController));

        // Only by owner
        try {
            await instance.setXChainParams(0, 0, homeChainZorroController, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    it('does not update pool if no elapsed blocks', async () => {
        // Add pool
        await instance.add(
            1,
            web3.utils.randomHex(20),
            true,
            web3.utils.randomHex(20)
        );

        // Simulate no elapsed blocks
        const currBlock = await web3.eth.getBlockNumber();
        await instance.setLastRewardBlock(0, currBlock + 100);

        // Call update pool
        const tx = await instance.updatePoolMod(0); 

        // Assert 0 ZOR minted
        const {logs} = tx;
        const {args} = logs[0];
        assert.equal(args._amount, 0);
    });
});

contract('ZorroController', async accounts => {
    let instance, vault, lpPool;

    const blocksPerDay = 30000;
    const distFactorMin = 1;
    const distFactorMax = 20; 
    const multiplierVal = 1;
    const USDCAddress = web3.utils.randomHex(20);

    before(async () => {
        const mockZorroToken = await MockZorroToken.deployed();
        instance = await MockZorroController.deployed();
        vault = await MockInvestmentVault.deployed();
        lpPool = await MockLPPool.deployed();

        // Vault config
        await vault.setZorroControllerAddress(instance.address);
        await vault.setWantAddress(lpPool.address);
        await vault.setBurnAddress(accounts[4]);

        // Set Oracle address
        await instance.setZorroControllerOracle(accounts[0]);

        // Set rewards params
        await instance.setRewardsParams(
            blocksPerDay,
            [distFactorMin, distFactorMax],
            1,
            10
        );
        // Set ZOR per block
        await instance.setZorroPerBlock(
            1,
            100e9,
            100,
            1e9,
            web3.utils.toWei('800000', 'ether')
        );
        // Add pool
        await instance.add(
            multiplierVal,
            lpPool.address,
            true,
            vault.address
        );
        // Set ZOR token address
        await instance.setKeyAddresses(
            mockZorroToken.address,
            USDCAddress
        );
    });

    it('updates pool rewards for xchain', async () => {
        // Expect correct amount of tokens to have been minted
        const ZORPerBlock = await instance.ZORROPerBlock.call();
        const poolBeforeUpdate = await instance.poolInfo.call(0);
        
        const tx = await instance.updatePoolMod(0);
        const currBlock = await web3.eth.getBlockNumber();
        const {logs} = tx;
        const {args} = logs[0];
        const mintedRewards = args._amount;
        assert.isTrue(mintedRewards.isZero());
        

        // Assert pool rewards correct
        const pool = await instance.poolInfo.call(0);
        const {accZORRORewards, lastRewardBlock} = pool;
        assert.isTrue(accZORRORewards.isZero());
        assert.equal(lastRewardBlock, currBlock);
    });
});

contract('ZorroController', async accounts => {
    let instance, vault, lpPool;

    const blocksPerDay = 30000;
    const distFactorMin = 1;
    const distFactorMax = 20; 
    const multiplierVal = 1;
    const USDCAddress = web3.utils.randomHex(20);
    
    before(async () => {
        const mockZorroToken = await MockZorroToken.deployed();
        instance = await MockZorroController.deployed();
        vault = await MockInvestmentVault.deployed();
        lpPool = await MockLPPool.deployed();

        // Vault config
        await vault.setZorroControllerAddress(instance.address);
        await vault.setWantAddress(lpPool.address);
        await vault.setBurnAddress(accounts[4]);

        // Set home chain
        await instance.setXChainParams(
            0,
            0,
            instance.address
        );
        // Set Oracle address
        await instance.setZorroControllerOracle(accounts[0]);

        // Set rewards params
        await instance.setRewardsParams(
            blocksPerDay,
            [distFactorMin, distFactorMax],
            1,
            10
        );
        // Set ZOR per block
        await instance.setZorroPerBlock(
            1,
            100e9,
            100,
            1e9,
            web3.utils.toWei('800000', 'ether')
        );
        // Add pool
        await instance.add(
            multiplierVal,
            lpPool.address,
            true,
            vault.address
        );
        // Set ZOR token address
        await instance.setKeyAddresses(
            mockZorroToken.address,
            USDCAddress
        );
    });

    it('updates pool rewards on chain', async () => {
        // Expect correct amount of tokens to have been minted
        const tx = await instance.updatePoolMod(0);
        const currBlock = await web3.eth.getBlockNumber();
        const {logs} = tx;
        const {args} = logs[0];
        const mintedRewards = args._amount;
        assert.equal(mintedRewards, 0);

        // Assert pool rewards correct
        const pool = await instance.poolInfo.call(0);
        const {accZORRORewards, lastRewardBlock} = pool;
        assert.isTrue(accZORRORewards.isZero());
        assert.equal(lastRewardBlock, currBlock);
    });
});