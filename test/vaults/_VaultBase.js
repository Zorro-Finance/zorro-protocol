// VaultBase tests
// Tests for all functions common to all vaults

const StargateUSDTOnAVAX = artifacts.require('StargateUSDTOnAVAX');

contract('VaultBase :: Setters', async accounts => {
    // Setup
    let vault;

    // Hook: Before all tests
    before(async () => {
        vault = await StargateUSDTOnAVAX.new();
        console.log('loaded vault: ', vault.address);
    });

    xit('Sets pool ID of underlying pool', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set the pid
        */

        /* THEN
        - The pid updates
        */
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