// VaultBase tests
// Tests for all functions common to all vaults

contract('VaultBase :: Setters', async accounts => {
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
    });

    it('Sets all key contract addresses', async () => {
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

    it('Sets price feed', async () => {
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

    it('Sets swap paths', async () => {
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

    it('Sets governor parameters', async () => {
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

    it('Sets fee settings', async () => {
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

    it('Sets slippage parameter', async () => {
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