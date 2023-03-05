// VaultBase tests
// Tests for all functions common to all vaults

// Artifacts
const StargateUSDTOnAVAXTest0 = artifacts.require('StargateUSDTOnAVAXTest0');
const VaultTimelock = artifacts.require('VaultTimelock');

contract('VaultBase :: Setters', async accounts => {
    // Setup
    let vault, vaultTimelock;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();
        
        // Get vault
        vault = await StargateUSDTOnAVAXTest0.deployed();
    });

    it('Sets pool ID of underlying pool', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set the pid
        */

        /* THEN
        - The pid updates
        */

        /* Test */
        // Setup
        const payload = vault.contract.methods.setPid(99).encodeABI();
        const salt = web3.utils.numberToHex(4096);

        // Run
        // Schedule timelock
        console.log('scheduling timelock...');
        await vaultTimelock.schedule(
            vault.address,
            0,
            payload,
            '0x',
            salt,
            0
        );
        // Execute timelock
        console.log('executing timelock...');
        await vaultTimelock.execute(
            vault.address,
            0,
            payload,
            '0x',
            salt
        );

        // Assert
        assert.equal(
            (await vault.pid.call()).toString(),
            '99'
        );
    });

    xit('Sets all key contract addresses', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set key contract addresses (e.g. token0, token1, defaultStablecoin, ZORROAddress, etc.)
        */

        /* THEN
        - Those values update on the contract
        */
    });

    xit('Sets price feed', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set a price feed for a particular token
        */

        /* THEN
        - The price feed address is updated in the mapping
        */
    });

    xit('Sets swap paths', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set a swap path for a particular origin and destination token
        */

        /* THEN
        - The swap path is updated
        */
    });

    xit('Sets governor parameters', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set the governor address and whether the governor is active
        */

        /* THEN
        - Those values update on the contract
        */
    });

    xit('Sets fee settings', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set fee settings (e.g. deosit, withdrawal, controller, buyback, and revshare rates)
        */

        /* THEN
        - Those values update on the contract
        */
    });

    xit('Sets slippage parameter', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set the slippage parameter
        */

        /* THEN
        - The slippage parameter value on the contract updates
        */
    });
});