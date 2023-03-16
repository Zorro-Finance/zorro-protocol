// VaultStandardAMM tests
// Tests for all functions common to AMM pair vaults

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    setDeployerAsZC,
    setZorroControllerAsZC,
    getUSDC,
    get_TJ_AVAX_USDC_LP,
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

contract('VaultStandardAMM :: Setters', async accounts => {
    let vault, vaultTimelock, zc;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();

        // Get vault
        vault = await TJ_AVAX_USDC.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();

        // Set Zorrocontroller as deployer (to auth the caller for deposits)
        await setDeployerAsZC(vault, vaultTimelock, accounts[0]);
    });

    // Hook: After all tests
    after(async () => {
        // Cleanup
        // Set Zorrocontroller back to actual ZorroController
        await setZorroControllerAsZC(vault, vaultTimelock, zc);
    });

    it('Sets whether LP token is farmable', async () => {
        /* GIVEN
        - As the timelock owner
        */

        /* WHEN
        - I set whether LP token is farmable
        */

        /* THEN
        - The vault contract toggles this value
        */

        /* Test */
        // Setup
        const isLPFarmable = await vault.isLPFarmable.call();

        // Run
        await callTimelockFunc(
            vaultTimelock, 
            vault.contract.methods.setIsFarmable(!isLPFarmable), 
            vault.address
        );

        // Assert
        assert.notEqual(await vault.isLPFarmable.call(), isLPFarmable);
    });
});

contract('VaultStandardAMM :: Investments', async accounts => {
    // Setup
    let vault, vaultActions, zc, masterchef, vaultTimelock, usdcERC20, iAVAX, pool, joeERC20;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();

        // Get vault
        vault = await TJ_AVAX_USDC.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();
        vaultActions = await VaultActionsStandardAMM.deployed();
        const routerAddress = await vaultActions.uniRouterAddress.call();
        const router = await IJoeRouter02.at(routerAddress);
        const { wavax, usdc, joe } = chains.avax.tokens;
        iAVAX = await IWETH.at(wavax);
        masterchef = await IBoostedMasterChefJoe.at(chains.avax.protocols.traderjoe.masterChef);
        joeERC20 = await ERC20Upgradeable.at(joe);

        // Establish contracts
        usdcERC20 = await ERC20Upgradeable.at(usdc);

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

        // Set pool
        pool = await ERC20Upgradeable.at(await vault.poolAddress.call());

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
        - I expect the want token to be farmed (and at the appropriate amount)
        - I expect the current want equity to be correct
        */

        /* Test */
        // Setup
        // Query LP token balance
        const balLP = await pool.balanceOf.call(accounts[0]);

        // Set deposit amount of LP token
        const amountLP = balLP.div(web3.utils.toBN(10));

        // Approve spending of LP token
        await pool.approve(vault.address, amountLP.mul(web3.utils.toBN(2)));

        // Run
        // Deposit 1
        console.log('bal LP before deposit 0: ', (await pool.balanceOf.call(accounts[0])).toString());
        await vault.depositWantToken(amountLP);
        const totalShares0 = await vault.sharesTotal.call();
        // Deposit 2
        console.log('bal LP before deposit 1: ', (await pool.balanceOf.call(accounts[0])).toString());
        console.log('curr want eq before deposit 1: ', (await vaultActions.currentWantEquity.call(vault.address)).toString());
        await vault.depositWantToken(amountLP);
        const totalShares1 = await vault.sharesTotal.call();
        const principalDebt1 = await vault.principalDebt.call();

        // Assert
        assert.approximately(
            totalShares1.toNumber(),
            amountLP.toNumber() * 2,
            1000, // tolerance
            'Total shares added approximately equivalent to number of want tokens added, minus fees'
        );

        assert.approximately(
            principalDebt.toNumber(),
            amountLP.toNumber() * 2,
            1000, // tolerance
            'Total principal debt should be the sum of cash flow in'
        );

        assert.equal(
            await pool.balanceOf.call(vault.address),
            web3.utils.toBN(0),
            'Vault should have zero want tokens because they should all have been farmed'
        );

        assert.equal(
            await vault.amountFarmed.call().toNumber(),
            amountLP.toNumber() * 2,
            '100% of want tokens should have been farmed to Masterchef contract'
        );
    });

    it('Exchanges USD to Want', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange USDC (stablecoin) for Want token
        */

        /* THEN
        - I expect USDC to be swapped for the Want token
        - I expect the want to be sent back to me
        */

        /* Test */

        // Setup
        // Get existing LP balance
        const balLP0 = await pool.balanceOf.call(accounts[0]);

        // Set usd amount, slippage
        const amountUSDC = web3.utils.toWei('10', 'Mwei'); // $10
        const slippage = 990;

        // Send usdc
        await usdcERC20.approve(vault.address, amountUSDC);

        // Run
        await vault.exchangeUSDForWantToken(amountUSDC, slippage);

        // Assert
        const balLP1 = await pool.balanceOf.call(accounts[0]);
        const netLP = balLP1.sub(balLP0);
        assert.isAbove(
            netLP.toNumber(),
            0,
            'A non zero amount of want tokens was obtained'
        );
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
        - I expect the amount removed, along with any rewards harvested, to be sent back to me
        */

        /* Tests */

        // Setup
        // Set deposit amount
        const balLP = await pool.balanceOf.call(accounts[0]);
        const amountLP = balLP.div(web3.utils.toBN(10));

        // Approve spending
        await pool.approve(vault.address, amountLP);

        // Deposit
        await vault.depositWantToken(amountLP);
        const principalDebt0 = await vault.principalDebt.call();
        
        // Check the current want equity
        const currWantEquity = await vaultActions.currentWantEquity.call(vault.address);
        const userInfo = await masterchef.userInfo.call(0, vault.address);
        // console.log('curr want equity: ', currWantEquity.toString(), 'userInfo: ', userInfo, 'amountLP: ', amountLP.toString());
        // Determine number of shares
        const totalShares0 = await vault.sharesTotal.call();
        const principalDebt1 = await vault.principalDebt.call();
        const amountFarmed0 = await vault.amountFarmed.call();
        const balLP0 = await pool.balanceOf.call(accounts[0]);
        
        // Run
        const sharesToRemove = totalShares0.mul(amountLP).div(currWantEquity);
        await vault.withdrawWantToken(sharesToRemove);
        for (let i=0; i<5; i++) {
            // Run updatePool() a few times to advance blocks and get rewards
            await masterchef.updatePool(0);
        }
        const totalShares1 = await vault.sharesTotal.call();
        const amountFarmed1 = await vault.amountFarmed.call();
        const balLP1 = await pool.balanceOf.call(accounts[0]);
        const joeReward = await joe.balanceOf(accounts[0]);

        // Assert
        const sharesRemoved = totalShares1.sub(totalShares0);
        const netPrincipalDebt = principalDebt1.sub(principalDebt0);
        const netAmountFarmed = amountFarmed1.sub(amountFarmed0);
        const netBalLP = balLP1.sub(balLP0);
        assert.approximately(
            sharesRemoved.toNumber(),
            amountLP.toNumber(),
            1000,
            'Shares removed should be approximately equal to the amount of LP removed'
        );
        
        assert.equal(
            netPrincipalDebt.toNumber(),
            amountLP.toNumber(),
            'Principal debt decremented by Want amount removed'
        );

        assert.equal(
            netAmountFarmed.toNumber(),
            -1 * amountLP.toNumber(),
            'Amount farmed on Masterchef should be completely unfarmed' 
        );
        
        assert.equal(
            netBalLP.toNumber(),
            amountLP.toNumber(),
            'Amount of LP returned to wallet corresponds to the number of shares requested on the withdrawal'
        );

        assert.isAbove(
            joeReward.toNumber(),
            0,
            'Joe rewards earned is > 0 and returned to wallet'
        )
    });

    it('Exchanges Want to USD', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I exchange Want token for USDC (stablecoin)
        */

        /* THEN
        - I expect Want token to be exchanged for USDC
        - I expect the USD token to be sent back to me
        */

        /* Test */

        // Setup
        // Calculate USDC balance beforehand
        const balUSDC0 = await usdcERC20.balanceOf.call(accounts[0]);

        // Set LP amount, slippage
        const balLP0 = await pool.balanceOf.call(accounts[0]);
        const amountLP = balLP0.div(web3.utils.toBN(10));
        const slippage = 990;

        // Approve spending
        await pool.approve(vault.address, amountLP);

        // Run
        await vault.exchangeWantTokenForUSD(amountLP, slippage);

        // Assert
        const balUSDC1 = await usdcERC20.balanceOf.call(accounts[0]);
        const netUSDC = balUSDC1.sub(balUSDC0);
        assert.isAbove(
            netUSDC.toNumber(),
            0,
            'Net USDC received after exchange is > 0'
        );
    });

    it('Fetches pending farm rewards', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I call pendingFarmRewards()
        */

        /* THEN
        - I expect to see the pending rewards owed to this vault
        */

        /* Test */
        // Setup 
        // Calculate rewards before depositing
        const joeRewards0 = await vault.pendingFarmRewards.call();
        console.log('joeRewards0: ', joeRewards0.toString());
        
        // Deposit
        const balLP0 = await pool.balanceOf.call(accounts[0]);
        const amountLP = balLP0.div(web3.utils.toBN(10));
        await pool.approve(vault.address, amountLP);
        await vault.depositWantToken(amountLP);
        
        // Run
        for (let i=0; i<5; i++) {
            // Update the pool a few times to advance the blocks and get rewards
            await masterchef.updatePool(0);
        }
        const joeRewards1 = await vault.pendingFarmRewards.call();
        console.log('joeRewards1: ', joeRewards1.toString());

        // Assert
        assert.isAbove(
            joeRewards1.sub(joeRewards0).toNumber(), 
            0,
            'Farm rewards are > 0'
        );
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