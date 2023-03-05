// VaultStargate tests
// Tests for all functions for Stargate vaults

// Imports
const {
    chains,
} = require('../../helpers/constants');

// Artifacts
const StargateUSDTOnAVAXTest0 = artifacts.require('StargateUSDTOnAVAXTest0');
const VaultTimelock = artifacts.require('VaultTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const VaultActionsStargate = artifacts.require('VaultActionsStargate');
const IJoeRouter02 = artifacts.require('IJoeRouter02');
const ZorroController = artifacts.require('ZorroController');

contract('VaultStargate :: Setters', async accounts => {
    xit('Sets key Stargate addresses', async () => {
        /* GIVEN
        - As the owner of the vault (timelock)
        */

        /* WHEN
        - I set the stargate key addresses (SG pool, router)
        */

        /* THEN
        - The addresses update successfully
        */
    });
});

contract('VaultStargate :: Investments', async accounts => {
    // Setup
    let vault, zc, vaultTimelock, usdtERC20;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();
        
        // Get vault
        vault = await StargateUSDTOnAVAXTest0.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();
        const vaultActions = await VaultActionsStargate.deployed();
        const routerAddress = await vaultActions.uniRouterAddress.call();
        const router = await IJoeRouter02.at(routerAddress);
        const {wavax, usdt} = chains.avax.tokens;
        const now = Math.floor((new Date).getTime() / 1000);
        console.log('amount AVAX in wallet: ', (await web3.eth.getBalance(accounts[0])).toString());
        await router.swapExactAVAXForTokens(
            0,
            [wavax, usdt],
            accounts[0],
            now + 300,
            {value: web3.utils.toWei('100', 'ether')}
        );

        usdtERC20 = await ERC20Upgradeable.at(usdt);
    });

    it('Deposits', async () => {
        /* GIVEN
        - As a Zorro Controller
        */

        /* WHEN
        - I deposit into this vault
        */

        /* THEN
        - I expect shares to be added, proportional to the size of the pool
        - I expect the total shares to be incremented by the above amount, accounting for fees
        - I expect the principal debt to be incremented by the Want amount deposited
        - I expect the want token to be farmed
        - I expect the supply and borrow balances to be updated
        */

        /* Test */
        // Setup
        // Set Zorrocontroller as deployer
        const payload = vault.contract.methods.setContractAddress(12, accounts[0]).encodeABI();
        const salt = web3.utils.numberToHex(4096);
        // Schedule timelock
        console.log('scheduling timelock...');
        await vaultTimelock.schedule(
            vault.address,
            0,
            payload,
            '0x',
            salt,
            0
        );
        // Execute timelock
        console.log('executing timelock...');
        await vaultTimelock.execute(
            vault.address,
            0,
            payload,
            '0x',
            salt
        );

        // Set deposit amount
        const amountUSDT = await usdtERC20.balanceOf.call(accounts[0]);
        console.log('amountUSDT: ', amountUSDT.toString());

        // Approve spending
        await usdtERC20.approve(vault.address, amountUSDT);

        // Run
        console.log(
            'want addr: ', await vault.wantAddress.call(),
            'pid: ', (await vault.pid.call()).toString(),
            'farmContractAddress: ', await vault.farmContractAddress.call(),
            'poolAddress: ', await vault.poolAddress.call(),
            'stargateRouter: ', await vault.stargateRouter.call(),
            'stargatePoolId: ', (await vault.stargatePoolId.call()).toString(),
            'earnedAddress: ', await vault.earnedAddress.call(),
            'pricefeed token0: ', await vault.priceFeeds.call(await vault.token0Address.call()),
            'pricefeed earned: ', await vault.priceFeeds.call(await vault.earnedAddress.call()),
        );
        await vault.depositWantToken(amountUSDT);

        // Assert
        // TODO

        // Cleanup
        // Set Zorrocontroller back to actual ZorroController
        // Set Zorrocontroller as deployer
        const payload1 = vault.contract.methods.setContractAddress(12, zc.address).encodeABI();
        const salt1 = web3.utils.numberToHex(4096);
        // Schedule timelock
        console.log('scheduling timelock...');
        await vaultTimelock.schedule(
            vault.address,
            0,
            payload1,
            '0x',
            salt1,
            0
        );
        // Execute timelock
        console.log('executing timelock...');
        await vaultTimelock.execute(
            vault.address,
            0,
            payload1,
            '0x',
            salt1
        );
    });

    xit('Exchanges USD to Want', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange USDC (stablecoin) for Want token
        */

        /* THEN
        - I expect USDC to be swapped for the Want token
        - I expect the USDC to be sent back to me
        */
    });

    xit('Withdraws', async () => {
        /* GIVEN
        - As a Zorro Controller
        */

        /* WHEN
        - I withdraw from this vault
        */

        /* THEN
        - I expect shares to be removed, proportional to the size of the pool
        - I expect the total shares to be decremented by the above amount, accounting for fees
        - I expect the principal debt to be decremented by the Want amount withdrawn
        - I expect the want token to be unfarmed
        - I expect the supply and borrow balances to be updated
        - I expect the amount removed, along with any rewards harvested, to be sent back to me
        */
    });

    xit('Exchanges Want to USD', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange Want token for USDC (stablecoin)
        */

        /* THEN
        - I expect Want token to be exchanged for USDC
        - I expect the Want token to be sent back to me
        */
    });
});

contract('VaultBase :: Earnings', async accounts => {
    xit('Autocompounds successfullly', async () => {
        /* GIVEN
        - As a public user
        - Enough blocks have elapsed such that harvestable earnings are present
        */

        /* WHEN
        - Calling the earn function
        */

        /* THEN
        - I expect the Want token to be fully unfarmed
        - I expect the correct amount of unfarmed token to be collected as controller fees
        - I expect the correct amount of unfarmed token to be bought back, adeed to ZOR liquidity, and LP token burned
        - I expect the correct amount of unfarmed token to be collected as revenue share and sent to the Zorro staking vault
        - I expect the remaining amount to be re-farmed
        */
    });
});