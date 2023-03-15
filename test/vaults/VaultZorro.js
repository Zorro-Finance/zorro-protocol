// VaultZorro tests
// Tests for all functions for the Zorro staking vault

// Imports
const {
    chains,
} = require('../../helpers/constants');

const {
    setDeployerAsZC,
    setZorroControllerAsZC,
    swapExactETHForTokens,
    callTimelockFunc,
} = require('../../helpers/vaults');

// Artifacts
const VaultZorro = artifacts.require('VaultZorro');
const VaultTimelock = artifacts.require('VaultTimelock');
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable');
const VaultActionsZorro = artifacts.require('VaultActionsZorro');
const IAMMRouter02 = artifacts.require('IAMMRouter02');
const IPCSMasterChef = artifacts.require('IPCSMasterChef');
const ZorroController = artifacts.require('ZorroController');
const Zorro = artifacts.require('Zorro');
const IWETH = artifacts.require('IWETH');
const IUniswapV2Factory = artifacts.require('IUniswapV2Factory');
const IUniswapV2Pair = artifacts.require('IUniswapV2Pair');
const FinanceTimelock = artifacts.require('FinanceTimelock');

contract('VaultZorro :: Investments', async accounts => {
    // Setup
    let vault, vaultActions, zc, masterchef, vaultTimelock, financeTimelock, busdERC20, iBNB, zorro, poolZORBNB;

    // Hook: Before all tests
    before(async () => {
        // Get timelock
        vaultTimelock = await VaultTimelock.deployed();
        financeTimelock = await FinanceTimelock.deployed();

        // Get vault
        vault = await VaultZorro.deployed();

        // Other contracts/tokens
        zc = await ZorroController.deployed();
        vaultActions = await VaultActionsZorro.deployed();
        const routerAddress = await vaultActions.uniRouterAddress.call();
        const router = await IAMMRouter02.at(routerAddress);
        const { wbnb, busd } = chains.bnb.tokens;
        iBNB = await IWETH.at(wbnb);
        masterchef = await IPCSMasterChef.at(chains.bnb.protocols.pancakeswap.masterChef);
        zorro = await Zorro.deployed();

        // Establish contracts
        busdERC20 = await ERC20Upgradeable.at(busd);

        // Get BUSD
        const amountBNB = 100;
        const amountBNBWei = web3.utils.toWei(amountBNB.toString(), 'ether');
        await swapExactETHForTokens(router, [wbnb, busd], accounts[0], amountBNBWei);

        // Make timelock request to set ZC 
        await callTimelockFunc(
            financeTimelock, 
            zorro.contract.methods.setZorroController(accounts[0]), 
            zorro.address
        );
        // Mint Zorro
        const mintableZOR = web3.utils.toWei('20', 'ether');
        const amountZOR = web3.utils.toWei('10', 'ether');
        await zorro.mint(accounts[0], mintableZOR);
        console.log('balZOR after minting: ', (await zorro.balanceOf.call(accounts[0])).toString());

        // Get ZOR-BNB pool
        factory = await IUniswapV2Factory.at(chains.bnb.infra.uniFactoryAddress);
        const pairZORBNB = await factory.getPair(zorro.address, wbnb);
        console.log('PCS ZOR BNB pair addr: ', pairZORBNB);
        poolZORBNB = await IUniswapV2Pair.at(pairZORBNB);

        // Add liquidity to ZOR BNB pool
        const now = Math.floor((new Date).getTime() / 1000);
        await zorro.approve(router.address, amountZOR);
        await router.addLiquidityETH(
            zorro.address,
            amountZOR,
            0,
            0,
            accounts[0],
            now + 300, 
            {
                value: web3.utils.toWei('1', 'ether'),
            }
        );

        // Set Zorrocontroller as deployer (to auth the caller for deposits)
        await setDeployerAsZC(vault, vaultTimelock, accounts[0]);
    });

    // Hook: After all tests
    after(async () => {
        // Cleanup
        // Set Zorrocontroller back to actual ZorroController
        await setZorroControllerAsZC(vault, vaultTimelock, zc);
        await callTimelockFunc(
            financeTimelock, 
            zorro.contract.methods.setZorroController(zc.address), 
            zorro.address
        );
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
        // Query LP token balance
        const balZOR = await zorro.balanceOf.call(accounts[0]);
        console.log('balZOR in deposits: ', balZOR.toString());

        // Set deposit amount of LP token
        const amountZOR = balZOR.div(web3.utils.toBN(10));

        // Approve spending of LP token
        await zorro.approve(vault.address, amountZOR);

        // Run
        await vault.depositWantToken(amountZOR);

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

        // Setup
        // Get existing LP balance
        const balZOR0 = await zorro.balanceOf.call(accounts[0]);

        // Set usd amount, slippage
        const amountBUSD = web3.utils.toWei('10', 'ether'); // $10
        console.log('balBUSD for exch USD to Want: ', (await busdERC20.balanceOf.call(accounts[0])).toString());
        const slippage = 100;

        // Send usdc
        await busdERC20.approve(vault.address, amountBUSD);

        // Run
        await vault.exchangeUSDForWantToken(amountBUSD, slippage);

        // Assert
        // TODO
        // const balLP = await pool.balanceOf.call(accounts[0]);
        // const netLP = balLP.sub(balLP0);
        // assert.approximately(netLP.toNumber(), 0, 100000); // Get back similar amount to what was put in
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

        // Setup
        // Record initial balance
        const balZOR0 = await zorro.balanceOf.call(accounts[0]);
        console.log('balZOR in withdraws: ', balZOR0.toString());

        // Set deposit amount
        const amountZOR = balZOR0.div(web3.utils.toBN(10));

        // Approve spending
        await zorro.approve(vault.address, amountZOR);

        // Deposit
        await vault.depositWantToken(amountZOR);

        // Check the current want equity
        const currWantEquity = await vaultActions.currentWantEquity.call(vault.address);
        const userInfo = await masterchef.userInfo.call(0, vault.address);
        // console.log('curr want equity: ', currWantEquity.toString(), 'userInfo: ', userInfo, 'amountLP: ', amountLP.toString());
        // Determine number of shares
        const totalShares = await vault.sharesTotal.call();
        console.log('totalShares: ', totalShares.toString());

        // Run
        await vault.withdrawWantToken(totalShares);

        // Assert
        // const balUSDT = await usdtERC20.balanceOf.call(accounts[0]);
        // const netUSDT = balUSDT.sub(balUSDT0);
        // assert.approximately(netUSDT.toNumber(), 0, 100000); // Tolerance: 1%
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
        // Calculate BUSD balance beforehand
        const balBUSD0 = await busdERC20.balanceOf.call(accounts[0]);

        // Set ZOR amount, slippage
        const balZOR0 = await zorro.balanceOf.call(accounts[0]);
        console.log('balZOR in withdraws: ', balZOR0.toString());
        const amountZOR = balZOR0.div(web3.utils.toBN(10));
        console.log('amountZOR: ', amountZOR.toString());
        const slippage = 100;

        // Approve spending
        await zorro.approve(vault.address, amountZOR);

        // Run
        await vault.exchangeWantTokenForUSD(amountZOR, slippage);

        // Assert
        // TODO
        // const balUSDC = await usdcERC20.balanceOf.call(accounts[0]);
        // const netUSDC = balUSDC.sub(balUSDC0);
        // assert.approximately(netUSDC.toNumber(), parseInt(amountUSDT), 100000);
    });
});