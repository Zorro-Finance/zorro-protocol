const VaultStandardAMM = artifacts.require('VaultStandardAMM');
const VaultFactoryStandardAMM = artifacts.require('VaultFactoryStandardAMM');

contract('VaultFactoryStandardAMM', async accounts => {
    it('creates a vault', async () => {
        // only owner
    });
});

contract('VaultStandardAMM', async accounts => {
    it('deposits Want token', async () => {
        // check auth
    });

    it('exchanges USD for Want token', async () => {
        // Check auth
    });

    it('selectively swaps based on token type', async () => {
        // _safeSwap()
        // Check auth
    });

    it('farms Want token', async () => {
        // Check auth
    });

    it('unfarms Earn token', async () => {
        // Check auth
    });

    it('withdraws Want token', async () => {
        // Check auth
    });

    it('sets Zorro LP pool address', async () => {
        // Check auth
    });

    it('exhcnages Want token for USD', async () => {
        // Check auth
    });

    it('auto compounds and earns', async () => {
        // Check auth
    });

    it('buys back Earn token, adds liquidity, and burns LP', async () => {
        // Check auth
    });

    it('shares revenue with ZOR stakers', async () => {
        // Check auth
    });

    it('swaps Earn token to USD', async () => {
        // Check auth
    });

    it('sets governor props', async () => {
        // Check auth
    });

    it('sets fees', async () => {
        // Check auth
    });

    it('reverses swap paths', async () => {

    });
});