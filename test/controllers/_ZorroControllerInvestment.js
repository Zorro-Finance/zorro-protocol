// ZorroControllerInvestment contract
// Includes all tests for deposits, withdrawals, transfers, and their cross chain counterparts

contract('ZorroController :: Setters', async accounts => {
    it('Only owner can set X chain endpoint contract address', async () => {
        /* Case 1: Authorized call should succeed */

        /* GIVEN 
        As the owner of the contract (timelock controller)
        */

        /* WHEN
        I attempt to set the Zorro X Chain endpoint address 
        */

        /* THEN
        I should see the address change to the new value 
        */

        /* Case 2: Malicious call should fail */

        /* GIVEN 
        As a random user (not the owner)
        */

        /* WHEN
        I attempt to set the Zorro X Chain endpoint address 
        */

        /* THEN
        I should get an error and the transaction should revert
        */
    });

    it('Only owner can set whether time multipliers are active', async () => {
        /* Case 1: Authorized call should succeed */

        /* GIVEN 
        As the owner of the contract (timelock controller)
        */

        /* WHEN
        I attempt to toggle the isTimeMultiplierActive state
        */

        /* THEN
        I should see the value change to the new value 
        */

        /* Case 2: Malicious call should fail */

        /* GIVEN 
        As a random user (not the owner)
        */

        /* WHEN
        I attempt to toggle the isTimeMultiplierActive state
        */

        /* THEN
        I should get an error and the transaction should revert
        */
    });
});

contract('ZorroController :: Deposits', async accounts => {
    it('Deposits Want token directly into a vault (aka "Core deposit")', async () => {
        /* GIVEN
        - As a public user
        - With a single vault available
        */

        /* WHEN
        - I obtain a Want token
        - I deposit it
        */

        /* THEN
        - I should have a tranche that owns shares in the vault
        - The shares should be worth approximately the value of Want tokens I put in
        */
    });

    it('Accepts Stablecoin and deposits into a vault (aka "Full Service deposit")', async () => {
        /* GIVEN
        - As a public user
        - With a single vault available
        */

        /* WHEN
        - I deposit USDC
        */

        /* THEN
        - I should have a tranche that owns shares in the vault proportional to what I put in
        - The shares should be worth approximately the value of what I put in
        */
    });
});

contract('ZorroController :: Withdrawals', async accounts => {
    it('Withdraws Want token directly from a vault (aka "Core withdrawal")', async () => {
        /* GIVEN
        - As a public user who has deposited into a vault already (and thus own a tranche on that vault)
        */

        /* WHEN 
        - I withdraw, electing to get Want tokens back 
        */

        /* THEN
        - I expect to receive the entirety of my investment in that tranche back to my wallet in the form of Want token
        - I should not have any shares left in the vault
        - There should not be any active tranches left
        */
    });

    it('Withdraws from vault into Stablecoin (aka "Full Service withdrawal")', async () => {
        /* GIVEN
        - As a public user who has deposited into a vault already (and thus own a tranche on that vault)
        */

        /* WHEN 
        - I withdraw, electing to get USDC back 
        */

        /* THEN
        - I expect to receive the entirety of my investment in that tranche back to my wallet in the form of USDC
        - I should not have any shares left in the vault
        - There should not be any active tranches left
        */
    });

    it('Withdraws all tranches from a given vault for a user', async () => {
        /* GIVEN
        - As a public user who has deposited MULTIPLE times into a vault already (and thus own a tranche on that vault)
        */

        /* WHEN 
        - I withdraw all funds from a vault (all tranches)
        */

        /* THEN
        - I expect to receive the entirety of my investment across all tranches back to my wallet in the form of Want token
        - I should not have any shares left in the vault
        - There should not be any active tranches left
        */
    });
});

contract('ZorroController :: Transfers', async accounts => {
    it('Transfers assets from one tranche to another vault', async () => {
        /* GIVEN 
        - As a public user who has deposited into a vault already
        */

        /* WHEN 
        - I transfer funds from vault A (for a single tranche) to vault B
        */

        /* THEN 
        - I expect the entirety of my funds to be withdrawn from vault A and deposited into vault B
        - I should not have any shares left in vault A, but should have shares in vault B, in a new tranche
        */
    });
});

contract('ZorroController :: XChain', async accounts => {
    it('Accepts X Chain withdrawal request to Stablecoin', async () => {
        /* GIVEN 
        - A deposited tranche associated with a foreign wallet account exists on this chain already
        */

        /* WHEN 
        - An incoming cross chain withdrawal request gets relayed from the Zorro X Chain endpoint contract
        */

        /* THEN 
        - I expect all the shares in the tranche should be withdrawn as USDC
        - The withdrawn USDC should be transferred back to the Zorro X Chain endpoint contract
        - Any cross chain ZOR rewards should be burned (as they will be minted on the other side)
        */
    });

    it('Accepts Stablecoin from X Chain endpoint and deposits into a vault', async () => {
        /* GIVEN 
        - A vault exists on this chain
        */

        /* WHEN 
        - An incoming cross chain deposit request gets relayed from the Zorro Cross Chain endpoint contract
        */

        /* THEN 
        - I expect a tranche to be created and shares to be added, according to the USDC provided
        */
    });

    it('Repatriates rewards harvested during a cross chain withdrawal', async () => {
        /* Case 1: Repatriation to the home chain */

        /* GIVEN
        - The current chain is the home chain
        */

        /* WHEN 
        - The Zorro X Chain endpoint contract requests to repatriate rewards
        */

        /* THEN 
        - Zorro tokens are fetched from the public pool and sent to destination on chain.
        */

        /* Case 2: Repatration to NON home chain */

        /* GIVEN
        - The current chain is NOT the home chain
        */

        /* WHEN 
        - The Zorro X Chain endpoint contract requests to repatriate rewards
        */

        /* THEN 
        - Zorro tokens are minted and sent to destination on chain.
        */
    });

    it('Handles accumulated cross chain rewards', async () => {
        /* GIVEN 
        - As the designated Zorro oracle contract
        */

        /* WHEN 
        - It calls the handleAccXChainRewards() function with stats on how many ZOR tokens have been minted and slashed to date
        */

        /* THEN 
        - It burns the number of tokens minted, minus the number of tokens slashed
        - Fetches from the public pool an amount of tokens equal to the number of tokens that have been slashed on other chains
        - Transfers this slashed amount to the Zorro staking vault
        */

    });
});
