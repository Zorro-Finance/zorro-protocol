// VaultTimelock contract
// Includes all tests for Timelock controller used to own vault contracts

contract('VaultTimelock', async accounts => {
    it('Can call a function on a vault contract it owns using the timelock mechanism', async () => {
        /* GIVEN
        - As a timelock user with role of proposer (1)
        - As a timelock user with role of executor (2)
        - A contract owned by a timelock controller
        */

        /* WHEN
        - As (1) I propose calling a non-bypassable function on the contract owned by the timelock
        - As (2), after the timelock period has ended, I execute the proposed call above
        */

        /* THEN
        - I expect the function to execute successfully
        */
    });
});

contract('VaultTimelock :: Bypasses', async accounts => {
    it('Can bypass timelock for invoking the earn() function on a vault', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for earnings, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    it('Can bypass timelock when invoking the farm() function on a vault', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for farming, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    it('Can bypass timelock when emergency pausing a vault', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for pausing, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    it('Can bypass timelock when unpausing a vault', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for unpausing, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });
});