// ZorroControllerXChainBase contract
// Includes all tests for common cross chain controller logic

contract('ZorroControllerXChainBase :: Setters', async accounts => {
    xit('Sets Zorro and Stablecoin token addresses', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the Zorro token and stablecoin addresses
        */

        /* THEN
        - I expect the Zorro and stablecoin addresses to update
        */
    });

    xit('Sets controller and public pool addresses', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the current chain controller, home chain controller, and public pool addresses
        */

        /* THEN
        - I expect the controller, home chain controller, and public pool addresses to update
        */
    });

    xit('Sets chain IDs', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the home chain and current chain IDs
        */

        /* THEN
        - I expect the current chain ID and home chain IDs to update
        */
    });

    xit('Set ZorroControllerXChainActions address', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the actions contract address
        */

        /* THEN
        - I expect the actions contract address to update
        */
    });

    xit('Sets controller contracts', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the on-chain controller contract address
        */

        /* THEN
        - I expect the controller address to update
        */
    });

    xit('Sets chain mapping', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the chain ID to address mapping
        */

        /* THEN
        - I expect the Zorro chain to LZ chain map to update
        - I expect the LZ chain to Zorro chain map to update
        */
    });

    xit('Sets Stargate pool mapping', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the Stargate pool mapping
        */

        /* THEN
        - I expect the mapping of Zorro to Stargate pool ID to update
        */
    });

    xit('Sets LayerZero parameters', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the LayerZero parameters
        */

        /* THEN
        - I expect the Stargate router, Stargate Swap Pool ID, and LZ endpoint to update
        */
    });

    xit('Sets chain type', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the chain type for a provided Zorro chain ID
        */

        /* THEN
        - I expect the chain type for the provided Zorro chain to update

        */
    });

    xit('Sets burn address', async () => {
        /* GIVEN
        - As the owner of the contract (timelock)
        */

        /* WHEN
        - I set the burn address
        */

        /* THEN
        - The burn address is updated
        */
    });
});