// VaultActionsLiqStakeLP tests
// Test for common utilities functions of vaults for liquid staking + LP staking

contract('VaultActionsLiqStakeLP :: Accounting', async accounts => {
    it('Calculates current want equity', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I query the current want equity
        */

        /* THEN
        - I receive the current unrealized position value in Want token units
        */
    });
});

contract('VaultActionsLiqStakeLP :: Investments', async accounts => {
    it('Performs liquid staking and adds synth token to LP pool', async () => {
        /* GIVEN
        - As a public user, with ETH
        */

        /* WHEN
        - I invoke liquidStakeAndAddLiq()
        */

        /* THEN
        - I expect that my wrapped ETH is unwrapped and staked, 
        then added lqiudity to the sETH-ETH pool, and the LP tokens get sent back to me
        */
    });

    it('Performs liquid UNstaking and removes synth token from LP pool', async () => {
        /* GIVEN
        - As a public user, with an sETH-ETH LP token
        */

        /* WHEN
        - I invoke removeLiqAndliquidUnstake()
        */

        /* THEN
        - I expect that my sETH-ETH LP token is converted to its underlying tokens, and wrapped ETH is returned back to me.
        */
    });
});