// ZorroControllerBase contract
// Includes all tests for common functionality/utilties for all the ZorroController contracts

contract('ZorroControllerBase :: Setters', async accounts => {
    it('Sets the Zorro and stablecoin token addresses', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the Zorro token and stablecoin token addresses
        */

        /* THEN
        - I expect the values to change to what I set them to
        */
    });

    it('Sets the burn address', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the burn address
        */

        /* THEN
        - The burn address reflects the value I set it to
        */
    });

    it('Sets the public pool and Zorro staking vault addresses', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I change the public pool address
        - I change the zorro staking vault address
        */

        /* THEN
        - The addresses change to their newly set value
        */
    });

    it('Sets the rewards start block', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the reward start block
        */

        /* THEN
        - The reward start block gets updated to the value I set
        */
    });

    it('Sets the ZorroControllerActions contract address', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the actions contract address
        */

        /* THEN
        - The address gets updated to the new value
        */
    });

    it('Sets the key rewards parameters', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the blocks per day, daily distribution factors, chain multiplier, and base reward rate
        - I set the target TVL capture rate
        */

        /* THEN
        - Blocks per day is set
        - Daily distribution factor min/max are set
        - Base reward rate is set
        - Chain multiplier is set
        - Target TVL capture rate is set
        */
    });

    it('Sets the key cross chain parameters', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */

        /* WHEN
        - I set the current chain ID, the home chain ID, and the home chain controller
        */

        /* THEN
        - I expect the chain ID, the home chain ID, and the home chain controller are updated
        */
    });

    it('Sets the ZorroController oracle address', async () => {
        /* GIVEN
        - As the contract owner (timelock)
        */
    
        /* WHEN
        - I set the Zorro controller oracle
        */
    
        /* THEN
        - The Zorro controller oracle address gets updated
        */
    });
    
    it('Sets the ZorroPerBlock parameter correctly and securely', async () => {
        /* GIVEN
        - As the Zorro controller oracle
        */
    
        /* WHEN
        - I set the Zorro per block parameter
        */
    
        /* THEN
        - It sets the Zorro per block correctly if between min/max rails
        - It sets the Zorro per block correctly if below min rail
        - It sets the Zorro per block correctly if abox max rail
        */
    });
});

contract('ZorroControllerBase :: Vault Management', async accounts => {
    it('Updates the reward state of a vault on the home chain', async () => {
        /* GIVEN
        - As a public user
        - On the home chain
        */

        /* WHEN
        - I call updateVault() for a given vault ID
        */

        /* THEN
        - The vault is updated with the appropriate accumulate ZOR rewards count
        - The lastRewardBlock number is the most recent block
        - The ZORRO rewards quantity is fetched from the public pool and sent to this controller address
        - The minted ZOR quantity should be zero
        */
    });

    it('Updates the reward state of a vault on a NON home chain', async () => {
        /* GIVEN
        - As a public user
        - On a chain OTHER than the home chain
        */

        /* WHEN
        - I call updateVault() for a given vault ID
        */

        /* THEN
        - The vault is updated with the appropriate accumulate ZOR rewards count
        - The lastRewardBlock number is the most recent block
        - The ZORRO rewards quantity is minted and sent to this controller address
        - The minted quantity is recorded on the contract so the Oracle can become aware
        */
    });

    it('Resets the slashed synthetic rewards', async () => {
        /* GIVEN
        - As the Zorro Controller Oracle
        - NOT on the home chain
        */

        /* WHEN
        - resetSyntheticRewardsSlashed() is called
        */

        /* THEN
        - The accSynthRewardsSlashed is burned
        - The variable accSynthRewardsSlashed is set to zero
        */
    });

    it('Resets the accumulated minted synthetic rewards', async () => {
        /* GIVEN
        - As the Zorro Controller Oracle
        - NOT on the home chain
        */

        /* WHEN
        - resetSyntheticRewardsMinted() is called
        */

        /* THEN
        - The variable accSynthRewardsMinted is set to zero
        */
    });
});