const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroControllerXChain.deployed();
    });

    it('sets token USDC', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setTokenUSDC(USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.tokenUSDC.call()), USDC);
        // Only by owner
        try {
            await instance.setTokenUSDC(USDC, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
    
    it('sets Zorro LP Pool other token', async () => {
        // Normal
        const zorroLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroLPPoolOtherToken(zorroLPPoolOtherToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPoolOtherToken.call()), zorroLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setZorroLPPoolOtherToken(zorroLPPoolOtherToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro staking vault', async () => {
        // Normal
        const zorroStakingVault = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroStakingVault(zorroStakingVault);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroStakingVault.call()), zorroStakingVault);
        // Only by owner
        try {
            await instance.setZorroStakingVault(zorroStakingVault, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets uni router address', async () => {
        // Normal
        const uniRouterAddress = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUniRouterAddress(uniRouterAddress);
        assert.equal(web3.utils.toChecksumAddress(await instance.uniRouterAddress.call()), uniRouterAddress);
        // Only by owner
        try {
            await instance.setUniRouterAddress(uniRouterAddress, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets swap path', async () => {
         // Normal
         const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const AVAX = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         await instance.setSwapPaths([USDC, AVAX, ZOR], [USDC, otherToken]);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(0)), USDC);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(1)), AVAX);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(2)), ZOR);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(0)), USDC);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(1)), otherToken);
         // Only by owner
         try {
             await instance.setSwapPaths([], [], { from: accounts[1] });
         } catch (err) {
             assert.include(err.message, 'caller is not the owner');
         }
    });

    xit('encodes x chain distribute earnings payload', async () => {

    });

    xit('sends x chain dist earnings request', async () => {

    });

    xit('receives x chain dist request', async () => {

    });

    xit('buys back + LP + earn', async () => {

    });

    xit('rev shares', async () => {

    });

    xit('removes slashed rewards', async () => {

    });

    xit('awards slashed rewards to stakers', async () => {

    });
});