// FinanceTimelock contract
// Includes all tests for Timelock controller used to own financial contracts (pools, vesting wallets, etc.)

contract('FinanceTimelock', async accounts => {
    it('Can call a function on a pool contract it owns using the timelock mechanism', async () => {
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