// VaultActions tests
// Test for common utilities functions of vaults

contract('VaultActions :: Setters', async accounts => {
    xit('Sets key addresses', async () => {
        /* GIVEN
        - As the owner (timelock) of the contract
        */

        /* WHEN
        - I set the Uni router address or the burn address
        */

        /* THEN
        - Their values update correctly
        */
    });
});

contract('VaultActions :: Utilities', async accounts => {
    xit('Adds liquidity to LP pool', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I join a liquidity pool with the specified input tokens and amounts
        */

        /* THEN
        - I expect the correct amount of LP token to be send to the specified recipient
        */
    });

    xit('Removes liquidity from LP pools', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exit an LP pool with the provided LP token and amount
        */

        /* THEN
        - I expect to receive the corresponding underlying tokens back, at the recipient address
        */
    });

    xit('Safely performs swaps', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - Performing a safeSwap operation and providing an input token
        */

        /* THEN
        - I expect the correct amount of the output token to be delivered to the specified destination address
        */
    });
});

contract('VaultActions :: Finance', async accounts => {
    xit('Distributes and reinvests earnings', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - Invoking the function to distribute and reinvest earnings
        */

        /* THEN
        - The appropriate want token remaining, x-chain buyback amount, and x-chain revshare amount is returned to me
        - The appropriate amount of earnings is bought back, used to add liquidity, and the resulting LP token is burned
        - The appropriate amount of earnings is shared as revenue to the Zorro Staking Vault
        */
    });
});

contract('VaultActions :: Analytics', async accounts => {
    xit('Calculates unrealized profits', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - Calling unrealizedProfits()
        */

        /* THEN
        - I expect to receive both the accumulated profit and the harvestable earnings amounts in return
        */
    });
});