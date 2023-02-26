// PoolTreasury contract
// Includes all tests for Zorro treasury pool

contract('PoolTreasury :: Setters', async accounts => {
    xit('Sets the treasury vesting wallet', async () => {
        /* GIVEN
        - As the owner (timelock proposer)
        */

        /* WHEN
        - I set the vesting wallet address (whose contract lists this contract as a beneficiary)
        */

        /* THEN
        - I expect the address to be updated
        */
    });
});

contract('PoolTreasury :: CashFlow', async accounts => {
    xit('Receives ETH', async () => {
        /* GIVEN
        - A treasury pool contract
        */

        /* WHEN
        - ETH (meaning the native coin on the chain) is sent to this contract
        */

        /* THEN
        - The contract is able to receive (e.g. it is payable)
        */
    });

    xit('Redeems ZOR rewards from the connected vesting wallet (only owner)', async () => {
        /* GIVEN
        - As the owner (timelock executor)
        */

        /* WHEN
        - I redeem vested ZOR rewards
        */

        /* THEN
        - I expect them to be transferred to me
        */
    });

    xit('Withdraws ETH (only owner)', async () => {
        /* GIVEN
        - As the owner (timelock executor)
        */

        /* WHEN
        - I redeem accumulated ETH (native coin)
        */

        /* THEN
        - I expect it to be transferred to the specified destination address, as long as it's payable
        */
    });

    xit('Withdraws ERC20 tokens (only owner)', async () => {
        /* GIVEN
        - As the owner (timelock executor)
        */

        /* WHEN
        - I redeem accumulated ERC20 tokens of my choosing (assuming there are multiple ERC20 tokens on this contract)
        */

        /* THEN
        - I expect them to be transferred to the specified destination address
        */
    });
});