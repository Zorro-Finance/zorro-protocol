// VaultStandardAMM tests
// Tests for all functions common to AMM pair vaults

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    setDeployerAsZC,
    setZorroControllerAsZC,
    swapExactETHForTokens,
} = require('../../helpers/vaults');

// Artifacts
const PCS_ZOR_BNB = artifacts.require('PCS_ZOR_BNB');
const VaultTimelock = artifacts.require('VaultTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const VaultActionsStandardAMM = artifacts.require('VaultActionsStandardAMM');
const IAMMRouter02 = artifacts.require('IAMMRouter02');
const ZorroController = artifacts.require('ZorroController');

contract('VaultStandardAMM :: Setters', async accounts => {
    xit('Sets whether LP token is farmable', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });
});

contract('VaultLending :: Investments', async accounts => {
    // Setup
    let vault, zc, vaultTimelock, busdERC20;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();

        // Get vault
        vault = await PCS_ZOR_BNB.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();
        const vaultActions = await VaultActionsStandardAMM.deployed();
        const routerAddress = await vaultActions.uniRouterAddress.call();
        const router = await IAMMRouter02.at(routerAddress);
        const { wbnb, busd } = chains.bnb.tokens;

        // Get BUSD
        const val = web3.utils.toWei('100', 'ether');
        await swapExactETHForTokens(router, [wbnb, busd], accounts[0], val);
        
        // Establish contracts
        busdERC20 = await ERC20Upgradeable.at(busd);

        // Set Zorrocontroller as deployer (to auth the caller for deposits)
        await setDeployerAsZC(vault);
    });

    // Hook: After all tests
    after(async () => {
        // Cleanup
        // Set Zorrocontroller back to actual ZorroController
        await setZorroControllerAsZC(vault, zc);
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
        // Wrap BNB

        // Get Zorro

        // Add liquidity to Zorro-BNB pool

        // Query LP token balance

        // Set deposit amount of LP token

        // Approve spending of LP token
        

        // Run
        await vault.depositWantToken(amountLPToken);

        // Assert
        // TODO
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
        - I expect the USDC to be sent back to me
        */

        /* Test */

        // Setup
        // Set usd amount, slippage
        const amountBUSD = web3.utils.toWei('10', 'ether'); // $10
        const slippage = 990;

        // Approve spending
        await busdERC20.approve(vault.address, amountBUSD);

        // Run
        await vault.exchangeUSDForWantToken(amountBUSD, slippage);

        // Assert
        // TODO: (lp token balance > 0)
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
        // Get LP token (TODO: Abstract out whatever logic was used for deposit() to get LP token)

        // Approve spending

        // Deposit

        // Determine number of shares
        const totalShares = await vault.sharesTotal.call();

        // Run
        await vault.withdrawWantToken(totalShares);

        // Assert
        // TODO: All other assertions
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
        - I expect the Want token to be sent back to me
        */

        /* Test */

        // Setup
        // Get LP token (same abstract method above)

        // Get LP bal, set slippage
        
        const slippage = 990;

        // Approve spending

        // Run
        await vault.exchangeWantTokenForUSD(amountLPToken, slippage);

        // Assert
        // TODO
    });

    xit('Fetches pending farm rewards', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I call pendingFarmRewards()
        */

        /* THEN
        - I expect to see the pending rewards owed to this vault
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