const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroControllerXChain.deployed();
    });

    it('sets key tokens', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setTokens([USDC, ZOR]);
        assert.equal(web3.utils.toChecksumAddress(await instance.defaultStablecoin.call()), USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.ZORRO.call()), ZOR);
        // Only by owner
        try {
            await instance.setTokens([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets key contracts', async () => {
        // Normal
        const homeChainCtrl = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const currentChainCtrl = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const publicPool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setKeyContracts([homeChainCtrl, currentChainCtrl, publicPool]);
        assert.equal(web3.utils.toChecksumAddress(await instance.homeChainZorroController.call()), homeChainCtrl);
        assert.equal(web3.utils.toChecksumAddress(await instance.currentChainController.call()), currentChainCtrl);
        assert.equal(web3.utils.toChecksumAddress(await instance.publicPool.call()), publicPool);
        // Only by owner
        try {
            await instance.setKeyContracts([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets chains', async () => {
        // Normal
        await instance.setChains([4, 1]);
        assert.equal(await instance.chainId.call(), 4);
        assert.equal(await instance.homeChainId.call(), 1);
        // Only by owner
        try {
            await instance.setChains([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets controller contract', async () => {
        // Normal
        const zorroChainId = 6;
        const controller = web3.utils.randomHex(30); // Non EVM address (e.g. 30 byte address)
        await instance.setControllerContract(zorroChainId, controller);
        assert.equal(await instance.controllerContractsMap.call(zorroChainId), controller);
        // Only by owner
        try {
            await instance.setControllerContract(zorroChainId, controller, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets LZ chain mapping', async () => {
        // Normal
        const zorroChainId = 6;
        const lzChainId = 22;
        await instance.setZorroChainToLZMap(zorroChainId, lzChainId);
        assert.equal(await instance.ZorroChainToLZMap.call(zorroChainId), lzChainId);
        assert.equal(await instance.LZChainToZorroMap.call(lzChainId), zorroChainId);
        // Only by owner
        try {
            await instance.setZorroChainToLZMap(zorroChainId, lzChainId, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Stargate dest pool IDs', async () => {
        // Normal
        const zorroChainId = 5;
        const stargatePoolId = 27;
        await instance.setStargateDestPoolIds(zorroChainId, stargatePoolId);
        assert.equal(await instance.stargateDestPoolIds.call(zorroChainId), stargatePoolId);
        // Only by owner
        try {
            await instance.setStargateDestPoolIds(zorroChainId, stargatePoolId, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets LZ params', async () => {
        // Normal
        const stargateRouter = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const stargateSwapPoolId = 27;
        const lzEndpoint = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setLayerZeroParams(stargateRouter, stargateSwapPoolId, lzEndpoint);
        assert.equal(web3.utils.toChecksumAddress(await instance.stargateRouter.call()), stargateRouter);
        assert.equal(await instance.stargateSwapPoolId.call(), stargateSwapPoolId);
        assert.equal(web3.utils.toChecksumAddress(await instance.layerZeroEndpoint.call()), lzEndpoint);
        // Only by owner
        try {
            await instance.setLayerZeroParams(stargateRouter, stargateSwapPoolId, lzEndpoint, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});