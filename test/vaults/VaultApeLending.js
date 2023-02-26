// VaultApeLending tests
// Tests for Apelending leveraged lending vaults

contract('VaultApeLending :: Investments', async accounts => {
    xit('Deposits', async () => {
        /* GIVEN
        - As a Zorro Controller
        */

        /* WHEN
        - I deposit into this vault
        */

        /* THEN
        - I expect shares to be added, proportional to the size of the pool
        - I expect the total shares to be incremented by the above amount, accounting for fees
        - I expect the principal debt to be incremented by the Want amount deposited
        - I expect the want token to be farmed
        - I expect the supply and borrow balances to be updated
        */
    });

    xit('Exchanges USD to Want', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange BUSD (stablecoin) for Want token
        */

        /* THEN
        - I expect BUSD to be swapped for the Want token
        - I expect the BUSD to be sent back to me
        */
    });

    xit('Withdraws', async () => {
        /* GIVEN
        - As a Zorro Controller
        */

        /* WHEN
        - I withdraw from this vault
        */

        /* THEN
        - I expect shares to be removed, proportional to the size of the pool
        - I expect the total shares to be decremented by the above amount, accounting for fees
        - I expect the principal debt to be decremented by the Want amount withdrawn
        - I expect the want token to be unfarmed
        - I expect the supply and borrow balances to be updated
        - I expect the amount removed, along with any rewards harvested, to be sent back to me
        */
    });

    xit('Exchanges Want to USD', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange Want token for BUSD (stablecoin)
        */

        /* THEN
        - I expect Want token to be exchanged for BUSD
        - I expect the Want token to be sent back to me
        */
    });

    xit('Claims any comptroller rewards', async () => {
        /* GIVEN
        - As the governor of the contract
        */

        /* WHEN
        - I call claimLendingRewards()
        */

        /* THEN
        - The rain maker contract claims all protocol rewards owed to this vault
        - I receive protocol rewards
        */
    });
});

contract('VaultBase :: Earnings', async accounts => {
    xit('Autocompounds successfullly', async () => {
        /* GIVEN
        - As a public user
        - Enough blocks have elapsed such that harvestable earnings are present
        */

        /* WHEN
        - Calling the earn function
        */

        /* THEN
        - I expect the Want token to be fully unfarmed
        - I expect the correct amount of unfarmed token to be collected as controller fees
        - I expect the correct amount of unfarmed token to be bought back, adeed to ZOR liquidity, and LP token burned
        - I expect the correct amount of unfarmed token to be collected as revenue share and sent to the Zorro staking vault
        - I expect the remaining amount to be re-farmed
        */
    });
});