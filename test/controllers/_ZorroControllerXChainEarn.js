// ZorroControllerXChainEarn contract
// Includes all tests for cross chain earn events

contract('ZorroControllerXChainEarn :: Setters', async accounts => {
    xit('Sets key addresses', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the Zorro LP pool token
        - I set the Zorro staking vault address
        - I set the Uni router address
        */

        /* THEN
        - I expect all addresses to be updated accordingly
        */
    });

    xit('Sets swap paths', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the swap path
        */

        /* THEN
        - I expect the stablecoin to Zorro path to be updated
        - I expect the stablecoin to Zorro LP pool token to be updated
        */
    });

    xit('Sets price feeds', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the price feeds
        */

        /* THEN
        - I expect the ZOR price feed address to update
        - I expect the ZOR LP pool price feed address to update
        - I expect the stablecoin price feed address to update
        */
    });
});

contract('ZorroControllerXChainEarn :: Sending', async accounts => {
    xit('Sends a cross chain earnings distribution request', async () => {
        /* GIVEN
        - As a vault
        - With specified buyback and revshare amounts
        - With specified slippage parameters
        */

        /* WHEN
        - I call the cross chain earnings request function
        */

        /* THEN
        - I expect a Stargate Swap to be called with the appropriate payload
        */
    });
});