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
const ZorroController = artifacts.require('ZorroController');
const Zorro = artifacts.require('Zorro');
const IWETH = artifacts.require('IWETH');
const IUniswapV2Factory = artifacts.require('IUniswapV2Factory');
const IUniswapV2Pair = artifacts.require('IUniswapV2Pair');
const FinanceTimelock = artifacts.require('FinanceTimelock');

contract('VaultZorro :: Investments', async accounts => {
    // Setup
    let vault, vaultActions, zc, vaultTimelock, financeTimelock, busdERC20, iBNB, zorro, poolZORBNB;

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

        // Set deposit amount of LP token
        const amountZOR = balZOR.div(web3.utils.toBN(10));

        // Approve spending of LP token
        await zorro.approve(vault.address, amountZOR.mul(web3.utils.toBN(2)));

        // Run
        // Deposit 1
        await vault.depositWantToken(amountZOR);
        const totalShares0 = await vault.sharesTotal.call();
        // Deposit 2
        await vault.depositWantToken(amountZOR);
        const totalShares1 = await vault.sharesTotal.call();
        const principalDebt1 = await vault.principalDebt.call();

        // Assert
        assert.approximately(
            totalShares1.toNumber(),
            amountZOR.toNumber() * 2,
            1000, // tolerance
            'Total shares added approximately equivalent to number of want tokens added, minus fees'
        );

        assert.approximately(
            principalDebt1.toNumber(),
            amountZOR.toNumber() * 2,
            1000, // tolerance
            'Total principal debt should be the sum of cash flow in'
        );

        assert.isAbove(
            (await zorro.balanceOf.call(vault.address)).toNumber(),
            0,
            'Vault should have > 0 want tokens'
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
        - I expect the USDC to be sent back to me
        */

        // Setup
        // Get existing LP balance
        const balZOR0 = await zorro.balanceOf.call(accounts[0]);

        // Set usd amount, slippage
        const amountBUSD = web3.utils.toWei('10', 'ether'); // $10
        const slippage = 990;

        // Send usdc
        await busdERC20.approve(vault.address, amountBUSD);

        // Run
        await vault.exchangeUSDForWantToken(amountBUSD, slippage);

        // Assert
        const balZOR1 = await pool.balanceOf.call(accounts[0]);
        const netZOR = balZOR1.sub(balZOR0);
        assert.isAbove(
            netZOR.toNumber(),
            0,
            'A non zero amount of ZOR tokens was obtained'
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
        */

        /* Tests */
        // Setup
        // Set deposit amount
        const balZOR = await zorro.balanceOf.call(accounts[0]);
        const amountZOR = balZOR.div(web3.utils.toBN(10));

        // Approve spending
        await zorro.approve(vault.address, amountZOR);

        // Deposit
        await vault.depositWantToken(amountZOR);
        const principalDebt0 = await vault.principalDebt.call();

        // Check the current want equity
        const currWantEquity = await vaultActions.currentWantEquity.call(vault.address);

        // Determine number of shares
        const totalShares0 = await vault.sharesTotal.call();
        const principalDebt1 = await vault.principalDebt.call();
        const amountFarmed0 = await vault.amountFarmed.call();
        const balZOR0 = await pool.balanceOf.call(accounts[0]);

        // Run
        const sharesToRemove = totalShares0.mul(amountLP).div(currWantEquity);
        await vault.withdrawWantToken(sharesToRemove);
        const totalShares1 = await vault.sharesTotal.call();
        const amountFarmed1 = await vault.amountFarmed.call();
        const balZOR1 = await pool.balanceOf.call(accounts[0]);

        // Assert
        const sharesRemoved = totalShares1.sub(totalShares0);
        const netPrincipalDebt = principalDebt1.sub(principalDebt0);
        const netAmountFarmed = amountFarmed1.sub(amountFarmed0);
        const netBalZOR = balZOR1.sub(balZOR1);

        assert.approximately(
            sharesRemoved.toNumber(),
            amountZOR.toNumber(),
            1000,
            'Shares removed should be approximately equal to the amount of want (Zorro) removed'
        );
        
        assert.equal(
            netPrincipalDebt.toNumber(),
            amountZOR.toNumber(),
            'Principal debt decremented by Want amount removed'
        );
        
        assert.equal(
            netBalZOR.toNumber(),
            amountZOR.toNumber(),
            'Amount of want returned to wallet corresponds to the number of shares requested on the withdrawal'
        );
    });

    it('Withdraws (revshare)', async () => {
        /* GIVEN
        - As a Zorro Controller
        */

        /* WHEN
        - I withdraw from this vault
        - After a revenue share transfer into the vault happened
        */

        /* THEN
        - I expect the amount removed to be sent back to me, 
          plus my share of any increase in the vault due to revenue sharing
        */

        /* Tests */
        // Setup
        // Set deposit amount
        const balZOR = await zorro.balanceOf.call(accounts[0]);
        const amountZOR = balZOR.div(web3.utils.toBN(10));

        // Approve spending
        await zorro.approve(vault.address, amountZOR);

        // Deposit
        await vault.depositWantToken(amountZOR);

        // Check the current want equity
        const totalShares0 = await vault.sharesTotal.call();

        // Run
        // Transfer ZOR to vault (simulate revshare)
        await zorro.transfer(vault.address, amountZOR.div(web3.utils.toBN(2)));

        // Withdrawa ZOR
        await vault.withdrawWantToken(totalShares0);
        const totalShares1 = await vault.sharesTotal.call();
        const balZOR1 = await pool.balanceOf.call(accounts[0]);

        // Assert
        assert.approximately(
            balZOR1.toNumber(),
            balZOR.toNumber(),
            'ZOR returned should equal ZOR deposited plus revshare'
        );

        assert.equal(
            totalShares1.toNumber(),
            0,
            'No shares should be left'
        );
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
        const amountZOR = balZOR0.div(web3.utils.toBN(10));
        const slippage = 100;

        // Approve spending
        await zorro.approve(vault.address, amountZOR);

        // Run
        await vault.exchangeWantTokenForUSD(amountZOR, slippage);

        // Assert
        const balBUSD1 = await busdERC20.balanceOf.call(accounts[0]);
        const netBUSD = balBUSD1.sub(balBUSD0);
        assert.isAbove(
            netBUSD.toNumber(),
            0,
            'Net BUSD received after exchange is > 0'
        );
    });
});