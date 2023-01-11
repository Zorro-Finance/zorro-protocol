// VaultTimelock contract
// Includes all tests for Timelock controller used to own vault contracts

contract('VaultTimelock', async accounts => {
    it('Can call a function on a vault contract it owns using the timelock mechanism', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });
});

contract('VaultTimelock :: Bypasses', async accounts => {
    it('Can bypass timelock for invoking the earn() function on a vault', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });

    it('Can bypass timelock when invoking the farm() function on a vault', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });

    it('Can bypass timelock when emergency pausing a vault', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });

    it('Can bypass timelock when unpausing a vault', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });
});