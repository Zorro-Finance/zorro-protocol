// ZorroControllerActions contract
// Includes all tests for ZorroController contract utilities

contract('ZorroControllerActions :: Investments', async accounts => {
    it('Calculates rewards due and slashed rewards for a given tranche', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - When calling getAdjustedRewards()
        */

        /* THEN
        - I expect to receive the correct number of rewards due and slashed rewards
        */
    });

    it('Calculates time multiplier factor for a given duration', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - When calling getTimeMultiplier
        */

        /* THEN
        - I expect to recieve an amount equal to (1 + sqrt(num_weeks)) * 1e12
        - I expect to receive simply 1e12 if the time multiplier is not active
        */
    });

    it('Calculate shares, adjusted for time multiplier', async () => {
        /* GIVEN
        - As a public user
        - A number of shares and a time multiplier value
        */

        /* WHEN
        - I call getUserContribution()
        */

        /* THEN
        - I expect to get an adjusted shares value of the shares times the time multiplier
        */
    });
});