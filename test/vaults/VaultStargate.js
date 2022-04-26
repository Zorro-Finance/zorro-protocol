const MockVaultStargate = artifacts.require('MockVaultStargate');
const MockVaultFactoryStargate = artifacts.require('MockVaultFactoryStargate');

contract('VaultFactoryStargate', async accounts => {
    let factory;
    let instance;

    before(async () => {
        factory = await MockVaultFactoryStargate.deployed();
        instance = await MockVaultStargate.deployed();
    });

    it('has a master vault', async () => {
        assert.equal(await factory.masterVault.call(), instance.address);
    });

    xit('creates a vault', async () => {
        // only owner
    });
});

contract('VaultStargate', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStargate.deployed();
    });

    xit('deposits Want token', async () => {
        // check auth
    });

    xit('exchanges USD for Want token', async () => {
        // Check auth
    });

    xit('withdraws Want token', async () => {
        // Check auth
    });

    xit('exchanges Want token for USD', async () => {
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

    xit('farms Want token', async () => {
        // Check auth
    });

    xit('unfarms Want token', async () => {
        // Check auth
    });
});