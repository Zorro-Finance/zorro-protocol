// ZorroControllerXChainDeposit contract
// Includes all tests for cross chain deposits

contract('ZorroControllerXChainDeposit :: Sending', async accounts => {
    it('Sends a cross chain deposit request', async () => {
        /* GIVEN
        - As a public user looking to make a cross chain depoist

        - To a pre-existing vault
        - For a cross chain wallet with the same address
        */

        /* WHEN
        - I send a cross chain deposit request
        */

        /* THEN
        - I expect a Stargate swap to be called with the appropriate payload
        */
    });
});