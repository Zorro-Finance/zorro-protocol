// VaultActions tests
// Test for common utilities functions of vaults

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    callTimelockFunc,
} = require('../../helpers/vaults');

// Artifacts
const TJ_AVAX_USDC = artifacts.require('TJ_AVAX_USDC');
const VaultTimelock = artifacts.require('VaultTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const VaultActionsStandardAMM = artifacts.require('VaultActionsStandardAMM');
const IJoeRouter02 = artifacts.require('IJoeRouter02');
const IBoostedMasterChefJoe = artifacts.require('IBoostedMasterChefJoe');
const ZorroController = artifacts.require('ZorroController');
const IWETH = artifacts.require('IWETH');

contract('VaultActions :: Setters', async accounts => {
    let vaultActions, vaultTimelock, zc;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();

        // Get vaultActions
        vaultActions = await VaultActionsStandardAMM.deployed();
    });

    it('Sets key addresses', async () => {
        /* GIVEN
        - As the owner (timelock) of the contract
        */

        /* WHEN
        - I set the Uni router address or the burn address
        */

        /* THEN
        - Their values update correctly
        */

        /* Test */
        // Setup 
        const newRouterAddr = '0x70f657164e5b75689b64b7fd1fa275f334f28e18';
        const newBurnAddr = '0xcac4CFDA055cDD57139086A0391e64B9a19781d2';

        // Run
        await callTimelockFunc(
            vaultTimelock,
            vaultActions.contract.methods.setUniRouterAddress(newRouterAddr),
            vaultActions.address
        );
        await callTimelockFunc(
            vaultTimelock,
            vaultActions.contract.methods.setBurnAddress(newBurnAddr),
            vaultActions.address
        );

        // Test
        assert.equal(await vaultActions.uniRouterAddress, newRouterAddr);
        assert.equal(await vaultActions.burnAddress, newBurnAddr);
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