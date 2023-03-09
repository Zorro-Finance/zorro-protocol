// VaultStargate tests
// Tests for all functions for Stargate vaults

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    setDeployerAsZC,
    setZorroControllerAsZC,
    swapExactAVAXForTokens,
} = require('../../helpers/vaults');

// Artifacts
const StargateUSDTOnAVAXTest0 = artifacts.require('StargateUSDTOnAVAXTest0');
const VaultTimelock = artifacts.require('VaultTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const VaultActionsStargate = artifacts.require('VaultActionsStargate');
const IJoeRouter02 = artifacts.require('IJoeRouter02');
const ZorroController = artifacts.require('ZorroController');
const IStargateLPStaking = artifacts.require('IStargateLPStaking');

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
    let vault, vaultActions, zc, vaultTimelock, usdtERC20, usdcERC20, iStargateLPStaking;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();

        // Get vault
        vault = await StargateUSDTOnAVAXTest0.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();
        vaultActions = await VaultActionsStargate.deployed();
        const routerAddress = await vaultActions.uniRouterAddress.call();
        const router = await IJoeRouter02.at(routerAddress);
        const { wavax, usdt, usdc } = chains.avax.tokens;
        const { lpStaking } = chains.avax.protocols.stargate;
        iStargateLPStaking = await IStargateLPStaking.at(lpStaking);

        // Get USDT
        const val = web3.utils.toWei('100', 'ether');
        await swapExactAVAXForTokens(router, [wavax, usdt], accounts[0], val);

        // Get USDC
        await swapExactAVAXForTokens(router, [wavax, usdc], accounts[0], val);
        
        // Establish contracts
        usdtERC20 = await ERC20Upgradeable.at(usdt);
        usdcERC20 = await ERC20Upgradeable.at(usdc);

        // Set Zorrocontroller as deployer (to auth the caller for deposits)
        await setDeployerAsZC(vault, vaultTimelock, accounts[0]);
    });

    // Hook: After all tests
    after(async () => {
        // Cleanup
        // Set Zorrocontroller back to actual ZorroController
        await setZorroControllerAsZC(vault, vaultTimelock, zc);
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
        // Set deposit amount
        const amountUSDT = web3.utils.toWei('10', 'Mwei'); // $10

        // Approve spending
        await usdtERC20.approve(vault.address, amountUSDT);

        // Run
        await vault.depositWantToken(amountUSDT);

        // Assert
        // TODO

    });

    it('Exchanges USD to Want', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange USDC (stablecoin) for Want token (USDT)
        */

        /* THEN
        - I expect USDC to be swapped for the Want token
        - I expect the USDT to be sent back to me
        */

        /* Test */

        // Setup
        // Get existing USDT balance
        const balUSDT0 = await usdtERC20.balanceOf.call(accounts[0]);

        // Set usd amount, slippage
        const amountUSDC = web3.utils.toWei('10', 'Mwei'); // $10
        const slippage = 990;

        // Send usdc
        await usdcERC20.transfer(vault.address, amountUSDC);

        // Run
        await vault.exchangeUSDForWantToken(amountUSDC, slippage);

        // Assert
        const balUSDT = await usdtERC20.balanceOf.call(accounts[0]);
        const netUSDT = balUSDT.sub(balUSDT0);
        assert.approximately(netUSDT.toNumber(), parseInt(amountUSDC), 100000);
    });

    it('Withdraws', async () => {
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

        /* Tests */

        // Setup
        // Record initial balance
        const balUSDT0 = await usdtERC20.balanceOf.call(accounts[0]);

        // Set deposit amount
        const amountUSDT = web3.utils.toWei('10', 'Mwei'); // $10

        // Approve spending
        await usdtERC20.approve(vault.address, amountUSDT);

        // Deposit
        await vault.depositWantToken(amountUSDT);

        // Check the current want equity
        const currWantEquity = await vaultActions.currentWantEquity.call(vault.address);
        const ledgerAmtRes = await iStargateLPStaking.userInfo.call(1, vault.address);
        console.log('curr want equity: ', currWantEquity.toString());
        console.log('lp staking ledger amount: ', ledgerAmtRes);
        // Determine number of shares
        const totalShares = await vault.sharesTotal.call();

        // Run
        const tx = await vault.withdrawWantToken(totalShares);
        console.log('full tx: ', JSON.stringify(tx.receipt.rawLogs));

        // Assert
        const balUSDT = await usdtERC20.balanceOf.call(accounts[0]);
        const netUSDT = balUSDT.sub(balUSDT0);
        assert.approximately(netUSDT.toNumber(), 0, 100000); // Tolerance: 1%
        // TODO: All other assertions
    });

    it('Exchanges Want to USD', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange Want token (USDT) for USDC (stablecoin)
        */

        /* THEN
        - I expect Want token to be exchanged for USDC
        - I expect the Want token to be sent back to me
        */

        /* Test */

        // Setup
        // Calculate USDC balance beforehand
        const balUSDC0 = await usdcERC20.balanceOf.call(accounts[0]);

        // Set usd amount, slippage
        const amountUSDT = web3.utils.toWei('10', 'Mwei'); // $10
        const slippage = 990;

        // Approve spending
        await usdtERC20.approve(vault.address, amountUSDT);

        // Run
        await vault.exchangeWantTokenForUSD(amountUSDT, slippage);

        // Assert
        const balUSDC = await usdcERC20.balanceOf.call(accounts[0]);
        const netUSDC = balUSDC.sub(balUSDC0);
        assert.approximately(netUSDC.toNumber(), parseInt(amountUSDT), 100000);
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