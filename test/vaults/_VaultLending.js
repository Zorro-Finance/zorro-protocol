// VaultLending tests
// Tests for all functions common to lending vaults

contract('VaultLending :: Setters', async accounts => {
    xit('Sets leverage parameters and rebalances position', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I set the target borrow limit and hysteresis
        */

        /* THEN
        - I expect the values to update
        - I expect the contract to rebalance its borrow position
        */
    });

    xit('Sets comptroller address', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I change the comptroller address
        */

        /* THEN
        - I expect the address to update on the contract
        */
    });

    xit('Sets lending token', async () => {
        /* GIVEN
        - As the owner (timelock) of the vault contract
        */

        /* WHEN
        - I change the address of the lending token
        */

        /* THEN
        - I expect the address to update on the contract
        */
    });

    xit('Updates supply and borrow balances', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I call updateBalance()
        */

        /* THEN
        - I expect the supply and borrow balances to be updated
        */
    });
});

contract('VaultLending :: Investments', async accounts => {
    xit('Rebalances when above target borrow envelope', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - When I deposit the Want token
        - When I withdraw the Want token
        */

        /* THEN
        - I expect the supply and borrow balances to be updated
        */
    });
});