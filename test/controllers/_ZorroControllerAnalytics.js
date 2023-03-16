// ZorroControllerAnalytics contract
// Includes all tests for calculating shares/rewards of Zorro investors

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    callTimelockFunc,
} = require('../../helpers/vaults');

// Artifacts
const TJ_AVAX_USDC = artifacts.require('TJ_AVAX_USDC');
const ControllerTimelock = artifacts.require('ControllerTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const ZorroController = artifacts.require('ZorroController');
const IWETH = artifacts.require('IWETH');

contract('ZorroController :: Analytics', async accounts => {
    let controllerTimelock, zc;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        controllerTimelock = await ControllerTimelock.deployed();

        // Controller
        zc = await ZorroController.deployed();

        // Other contracts, vars
        const { wavax, usdc } = chains.avax.tokens;
        const iAVAX = await IWETH.at(wavax);
        const usdcERC20 = await ERC20Upgradeable.at(usdc);

        // Get vault info
        const vault = await TJ_AVAX_USDC.deployed();
        const vid = await zc.vaultMapping.call(vault.address);
        const vaultInfo = await zc.vaultInfo.call(vid);
        const pool = await ERC20Upgradeable.at(vaultInfo.want);
        

        // Get USDC
        await getUSDC(
            web3.utils.toBN(web3.utils.toWei('100', 'ether')),
            router,
            accounts[0],
            web3
        );

        // Get LP
        await get_TJ_AVAX_USDC_LP(
            web3.utils.toBN(web3.utils.toWei('10', 'ether')),
            usdcERC20,
            iAVAX,
            router,
            accounts[0],
            web3
        );

        // Prepare want amount and approve
        const wantAmt = await pool.balanceOf.call(accounts[0]).div(10);
        await pool.approve(zc.address, wantAmt);

        // Deposit vault
        await zc.deposit(
            vid, 
            wantAmt,
            0
        );
    });

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