const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');
const MockVaultFactoryStandardAMM = artifacts.require('MockVaultFactoryStandardAMM');

contract('VaultFactoryStandardAMM', async accounts => {
    let factory;
    let instance;

    before(async () => {
        factory = await MockVaultFactoryStandardAMM.deployed();
        instance = await MockVaultStandardAMM.deployed();
    });

    it('has a master vault', async () => {
        assert.equal(await factory.masterVault.call(), instance.address);
    });

    xit('creates a vault', async () => {
        // only owner
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance; 

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
    });

    xit('deposits Want token', async () => {
        // check auth
    });

    xit('exchanges USD for Want token', async () => {
        // Check auth
    });

    xit('selectively swaps based on token type', async () => {
        // _safeSwap()
        // Check auth
    });

    xit('farms Want token', async () => {
        // Check auth
    });

    xit('unfarms Earn token', async () => {
        // Check auth
    });

    xit('withdraws Want token', async () => {
        // Check auth
    });

    xit('exhcnages Want token for USD', async () => {
        // Check auth
    });

    xit('auto compounds and earns', async () => {
        // Check auth
    });

    xit('buys back Earn token, adds liquidity, and burns LP', async () => {
        // Check auth
    });

    xit('shares revenue with ZOR stakers', async () => {
        // Check auth
    });

    xit('swaps Earn token to USD', async () => {
        // Check auth
    });

    xit('reverses swap paths', async () => {

    });
});