// ControllerTimelock contract
// Includes all tests for Timelock controller used to own controller contracts

contract('ControllerTimelock', async accounts => {
    xit('Can call a function on a controller contract it owns using the timelock mechanism', async () => {
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

contract('ControllerTimelock :: Bypasses', async accounts => {
    xit('Can bypass timelock for updating vault rewards', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for updating vault rewards on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    xit('Can bypass timelock when mass updating vault rewards', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for mass updating vault rewards on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    xit('Can bypass timelock when adding a new vault', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for adding a new vault, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    xit('Can bypass timelock when setting the controller contract', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for setting the controller contract, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    xit('Can bypass timelock when setting the cross chain mapping', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for setting the cross chain mapping, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });

    xit('Can bypass timelock when setting Stargate and LayerZero parameters', async () => {
        /* GIVEN
        - As a timelock user with role of proposer AND executor
        - A contract owned by a timelock controller
        */

        /* WHEN
        - I call a bypassable function for setting the Stargate/L0 params, on the timelock controller contract
        */

        /* THEN
        - It calls the destination function on the contract owned by the timelock without delay.
        */
    });
});