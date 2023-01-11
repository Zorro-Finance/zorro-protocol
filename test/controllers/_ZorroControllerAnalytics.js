// ZorroControllerAnalytics contract
// Includes all tests for calculating shares/rewards of Zorro investors

contract('ZorroController :: Analytics', async accounts => {
    it('Calculates pending Zorro rewards for a single tranche', async () => {
        /* GIVEN
        - As a public user who has invested into a vault
        */

        /* WHEN
        - I call pendingZORRORewards() for a single tranche ID
        */

        /* THEN
        - I expect to receive the correct number of harvestable rewards based on emission rate, multipliers, etc.
        */
    });

    it('Calculates pending Zorro rewards for multiple tranches', async () => {
        /* GIVEN
        - As a public user who has invested into a vault multiple times
        */

        /* WHEN
        - I call pendingZORRORewards() for all tranches
        */

        /* THEN
        - I expect to receive the correct number of harvestable rewards based on emission rate, multipliers, etc. summed across all tranches I own on this vault
        */
    });

    it('Gets number of shares for an account on a single tranche', async () => {
        /* GIVEN
        - As a public user who has invested into a vault
        */

        /* WHEN
        - I call shares() for a single tranche ID
        */

        /* THEN
        - I expect to receive the correct number of shares based on how much I have invested
        */
    });

    it('Gets number of shares for an account across multiple tranches', async () => {
        /* GIVEN
        - As a public user who has invested into a vault
        */

        /* WHEN
        - I call shares() for all tranches
        */

        /* THEN
        - I expect to receive the correct number of shares based on how much I have invested, summed across all tranches
        */
    });
});