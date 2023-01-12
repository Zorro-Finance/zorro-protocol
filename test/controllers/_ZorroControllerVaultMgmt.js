// ZorroControllerVaultMgmt contract
// Includes all tests for adding and updating vaults

contract('ZorroControllerVaultMgmt :: Vaults', async accounts => {
    it('Adds a new vault', async () => {
        /* GIVEN
        - As an owner (timelock) of the contract
        - A pre-existing vault
        */

        /* WHEN
        - I add a new vault
        */

        /* THEN
        - I should see a new vault in the vaultInfo list
        - The totalMultiplier number should change
        - Both this vault and the pre-existing vault should have their rewards updated
        - The vault's contract address is mapped to an ID
        */
    });

    it('Updates a vault with a new multiplier value', async () => {
        /* GIVEN
        - As an owner (timelock) of the contract
        - A pre-existing vault
        */

        /* WHEN
        - I update the existing vault's multiplier (aka "allocationPoint")
        */

        /* THEN
        - I expect the vault's multiplier to change
        - I expect the totalMultiplier number to change as a result
        */
    });
});