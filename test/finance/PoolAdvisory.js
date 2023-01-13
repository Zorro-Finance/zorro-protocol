// PoolAdvisory contract
// Includes all tests for Zorro advisory pool

contract('PoolAdvisory', async accounts => {
    it('Registers new advisors with the appropriate amount of shares', async () => {
        /* GIVEN
        - As the owner (timelock proposer)
        - With ZOR tokens already stored on this contract
        */

        /* WHEN
        - I create a new advisor with their beneficiary address
        */

        /* THEN
        - A vesting wallet is created that lists their provided address as a beneficiary
        - The vesting wallet has the requested number of ZOR tokens transferred to it
        */
    });
});