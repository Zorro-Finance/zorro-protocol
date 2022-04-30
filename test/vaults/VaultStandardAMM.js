const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');
const MockVaultFactoryStandardAMM = artifacts.require('MockVaultFactoryStandardAMM');
const MockAMMFarm = artifacts.require('MockAMMFarm');
const zeroAddress = '0x0000000000000000000000000000000000000000';
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockUSDC = artifacts.require('MockUSDC');
const MockAMMToken0 = artifacts.require('MockAMMToken0');
const MockAMMToken1 = artifacts.require('MockAMMToken1');
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggToken1 = artifacts.require('MockPriceAggToken1');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');

const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(uint256,uint256)');
const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
const approvalEventSig = web3.eth.abi.encodeEventSignature('Approval(address,address,uint256)');
const swappedEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const addedLiqEventSig = web3.eth.abi.encodeEventSignature('AddedLiquidity(uint256,uint256,uint256)');

const setupContracts = async (accounts) => {
    // Router
    const router = await MockAMMRouter02.deployed();
    await router.setBurnAddress(accounts[4]);
    // USDC
    const usdc = await MockUSDC.deployed();
    // Tokens
    const token0 = await MockAMMToken0.deployed();
    const token1 = await MockAMMToken1.deployed();
    // Farm contract
    const farmContract = await MockAMMFarm.deployed();
    await farmContract.setWantAddress(router.address);
    await farmContract.setBurnAddress(accounts[4]);
    // Vault
    const instance = await MockVaultStandardAMM.deployed();
    await instance.setWantAddress(router.address);
    await instance.setFarmContractAddress(farmContract.address);
    await instance.setUniRouterAddress(router.address);
    await instance.setToken0Address(token0.address);
    await instance.setToken1Address(token1.address);
    await instance.setTokenUSDCAddress(usdc.address);
    // Set controller
    await instance.setZorroControllerAddress(accounts[0]);
    // Price feeds
    const token0PriceFeed = await MockPriceAggToken0.deployed();
    const token1PriceFeed = await MockPriceAggToken1.deployed();
    const earnTokenPriceFeed = await MockPriceAggEarnToken.deployed();
    const ZORPriceFeed = await MockPriceAggZOR.deployed();
    const lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
    await instance.setPriceFeed(0, token0PriceFeed.address);
    await instance.setPriceFeed(1, token1PriceFeed.address);
    await instance.setPriceFeed(2, earnTokenPriceFeed.address);
    await instance.setPriceFeed(3, ZORPriceFeed.address);
    await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed.address);
    // Swap paths
    await instance.setSwapPaths(0, [usdc.address, token0.address]);
    await instance.setSwapPaths(1, [usdc.address, token1.address]);

    return {
        instance,
        router,
        farmContract,
        usdc,
        token0,
        token1,
    };
}

contract('VaultFactoryStandardAMM', async accounts => {
    let factory;
    let instance;
    const initVal = {
        pid: 0,
        isHomeChain: true,
        keyAddresses: {
            govAddress: accounts[0],
            zorroControllerAddress: zeroAddress,
            ZORROAddress: zeroAddress,
            zorroStakingVault: zeroAddress,
            wantAddress: zeroAddress,
            token0Address: zeroAddress,
            token1Address: zeroAddress,
            earnedAddress: zeroAddress,
            farmContractAddress: zeroAddress,
            rewardsAddress: zeroAddress,
            poolAddress: zeroAddress,
            uniRouterAddress: zeroAddress,
            zorroLPPool: zeroAddress,
            zorroLPPoolOtherToken: zeroAddress,
            tokenUSDCAddress: zeroAddress,
        },
        earnedToZORROPath: [],
        earnedToToken0Path: [],
        earnedToToken1Path: [],
        USDCToToken0Path: [],
        USDCToToken1Path: [],
        earnedToZORLPPoolOtherTokenPath: [],
        earnedToUSDCPath: [],
        fees: {
            controllerFee: 0,
            buyBackRate: 0,
            revShareRate: 0,
            entranceFeeFactor: 0,
            withdrawFeeFactor: 0,
        },
        priceFeeds: {
            token0PriceFeed: zeroAddress,
            token1PriceFeed: zeroAddress,
            earnTokenPriceFeed: zeroAddress,
            ZORPriceFeed: zeroAddress,
            lpPoolOtherTokenPriceFeed: zeroAddress,
        },
    };

    before(async () => {
        factory = await MockVaultFactoryStandardAMM.deployed();
        instance = await MockVaultStandardAMM.deployed();
    });

    it('has a master vault', async () => {
        assert.equal(await factory.masterVault.call(), instance.address);
    });

    it('creates a vault', async () => {
        // Create vault
        await factory.createVault(accounts[0], initVal);

        // Check creation
        assert.equal(await factory.numVaults.call(), 1);
        assert.isNotNull(await factory.deployedVaults.call(0));

        // Only owner
        try {
            await factory.createVault(accounts[0], initVal, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
    });

    it('deposits Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(account, 0);
        } catch (err) {
            assert.include(err.message, 'Want dep < 0');
        }

        // Mint some tokens
        await router.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await router.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

        /* First deposit */
        // Deposit
        const tx = await instance.depositWantToken(account, wantAmt);

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred;
        let farmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred) {
                transferred = rl;
            } else if (topics[0] === depositedEventSig) {
                farmed = rl;
            }
        }

        // Assert: transfers Want token
        assert.equal(web3.utils.toChecksumAddress(web3.utils.toHex(web3.utils.toBN(transferred.topics[1]))), accounts[0]);
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));

        // Assert: increments shares (total shares and user shares)
        assert.isTrue((await instance.sharesTotal.call()).eq(wantAmt));
        assert.isTrue((await instance.userShares.call(account)).eq(wantAmt));

        // Assert: calls farm()
        assert.isNotNull(farmed);

        /* Next deposit */
        // Set fees
        await instance.setFeeSettings(
            9990, // 0.1% deposit fee
            10000,
            0,
            0
        );
        // Deposit
        await instance.depositWantToken(account, wantAmt);

        // Assert: returns correct shares added (based on current shares etc.)
        const sharesTotal = wantAmt; // Total shares before second deposit
        const wantLockedTotal = wantAmt; // Total want locked before second deposit
        const sharesAdded = wantAmt.mul(sharesTotal).mul(web3.utils.toBN(9990)).div(wantLockedTotal.mul(web3.utils.toBN(10000)));
        const newTotalShares = web3.utils.toBN(sharesAdded).add(wantAmt);
        assert.isTrue((await instance.sharesTotal.call()).eq(newTotalShares));
        assert.isTrue((await instance.userShares.call(account)).eq(newTotalShares));

        /* Only Zorro controller */
        try {
            await instance.depositWantToken(zeroAddress, 0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });

    // TODO: test for distributeFees()

    it('withdraws Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentUserShares = await instance.userShares.call(account);
        const currentWantLockedTotal = await instance.wantLockedTotal.call();

        /* Withdraw 0 */
        try {
           await instance.withdrawWantToken(account, 0); 
        } catch (err) {
            assert.include(err.message, 'want amt <= 0');
        }
        
        /* Withdraw > 0 */
        
        // Withdraw
        const tx = await instance.withdrawWantToken(account, wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        let transferred;
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            } else if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: Correct sharesTotal and userShares
        const sharesRemoved = wantAmt.mul(currentSharesTotal).div(currentWantLockedTotal);
        const expectedSharesTotal = currentSharesTotal.sub(sharesRemoved);
        const expectedUserShares = currentUserShares.sub(sharesRemoved);
        assert.isTrue((await instance.sharesTotal.call()).eq(expectedSharesTotal));
        assert.isTrue((await instance.userShares.call(account)).eq(expectedUserShares));

        // Assert: calls unfarm()
        assert.isNotNull(unfarmed);

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));
    });

    it('withdraws safely when excess Want token specified', async () => {
        // Prep
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentUserShares = await instance.userShares.call(account);
        const currentWantLockedTotal = await instance.wantLockedTotal.call();
        const wantAmt = currentWantLockedTotal.add(web3.utils.toBN(1e12)); // Set to exceed the tokens locked, intentionally

        /* Withdraw > wantToken */

        // Withdraw
        const tx = await instance.withdrawWantToken(account, wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        let transferred;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            }
        }

        // Assert: Correct sharesTotal and userShares
        assert.isTrue((await instance.sharesTotal.call()).isZero());
        assert.isTrue((await instance.userShares.call(account)).isZero());

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(currentWantLockedTotal));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router, usdc;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
        usdc = setupObj.usdc;
    });

    it('exchanges USD for Want token', async () => {
        /* Prep */
        const amountUSD = web3.utils.toBN(web3.utils.toWei('100', 'ether'));

        // TODO: Probably need exchange rates to be set

        /* Exchange (0) */
        try {
            await instance.exchangeUSDForWantToken(0, 990);
        } catch (err) {
            assert.include(err.message, 'USDC deposit must be > 0');
        }

        /* Exchange (> balance) */
        try {
            await instance.exchangeUSDForWantToken(amountUSD, 990);
        } catch (err) {
            assert.include(err.message, 'USDC desired exceeded bal');
        }

        /* Exchange (> 0) */
        // Record Want bal pre exchange
        const preExchangeWantBal = await router.balanceOf.call(accounts[0]);
        // Transfer USDC
        await usdc.mint(accounts[0], amountUSD);
        await usdc.transfer(instance.address, amountUSD);
        // Exchange
        const tx = await instance.exchangeUSDForWantToken(amountUSD, 990);

        // Logs
        const { rawLogs } = tx.receipt;

        let swappedTokens = [];
        let addedLiq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === swappedEventSig) {
                if (web3.utils.toBN(topics[2]).eq(amountUSD.div(web3.utils.toBN(2)))) {
                    swappedTokens.push(rl);
                }
            } else if (topics[0] === addedLiqEventSig) {
                addedLiq = rl;
            }
        }

        // Assert: Swap event for tokens 0 and 1
        assert.equal(swappedTokens.length, 2);
        
        // Assert: Liquidity added
        assert.isNotNull(addedLiq);


        // Assert: Want token obtained
        const postExchangeWantBal = await router.balanceOf.call(accounts[0]);
        const expLiquidity = web3.utils.toBN(web3.utils.toWei('1', 'ether'));
        assert.isTrue(postExchangeWantBal.sub(preExchangeWantBal).eq(expLiquidity))

        /* Only Zorro Controller */
        try {
            await usdc.mint(accounts[0], amountUSD);
            await usdc.transfer(instance.address, amountUSD);
            await instance.exchangeUSDForWantToken(amountUSD, 990);
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
    });

    xit('exchanges Want token for USD', async () => {
        /* Prep */
        
        /* Exchange (0) */
        

        /* Exchange (> 0) */
        // Transfer Want token
        // Exchange
        // Simulate tokens 0, 1 bal by minting some tokens

        // Assert: Liquidity removed
        // Assert: Tokens 0, 1 obtained
        // Assert: Approvals called for tokens 0 and 1
        // Assert: Swap event for tokens 0 and 1
        // Assert: USDC obtained

        /* Only Zorro Controller */
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
    });

    xit('auto compounds and earns', async () => {
        /* Prep */

        /* Earn */
        // Earn
        // Assert: Harvests Earn token
        // Simulate: harvested earn tokens (mint some Earn tokens)
        // Assert: Distributes fees
        // Assert: Buys back
        // Assert: Revshares
        // Assert: Approves router for earned token
        // Assert: swaps tokens 0, 1
        // Assert: Adds liquidity
        // Assert: Updates last earn block
        // Assert: Re-Farms want token
    });
    // TODO: Do this for the case where one of tokens 0,1 is the Earn token
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
    });

    xit('buys back Earn token, adds liquidity, and burns LP', async () => {
        /* Prep */
        // Mint some Earned token to instance

        /* Buyback */
        // Buyback
        // Assert: Approval for earned token to router
        // Assert: Swapped in to ZOR, other token
        // Simulate: bal of ZOR, other token by minting
        // Assert: Added liquidity
    });

});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
    });

    xit('shares revenue with ZOR stakers', async () => {
        /* Prep */

        /* RevShare */
        // RevShare
        // Assert: Approval
        // Assert: Swapped to ZOR
    });

});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
    });

    xit('swaps Earn token to USD', async () => {
        /* Prep */

        /* SwapEarnedToUSDC */
        // Swap
        // Assert: Approval
        // Assert: Swap
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
    });

    it('farms Want token', async () => {
        // Mint tokens
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.628', 'ether'));
        await router.mint(instance.address, wantAmt);
        // Farm
        const tx = await instance.farm();
        const { rawLogs } = tx.receipt;

        let depositedInFarm;
        let approvedSpending;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === depositedEventSig) {
                depositedInFarm = rl;
            } else if (topics[0] === approvalEventSig && !approvedSpending) {
                approvedSpending = rl;
            }
        }

        // Assert: Increments Want locked total
        assert.isTrue((await instance.wantLockedTotal.call()).eq(wantAmt));

        // Assert: Allows farm contract to spend
        assert.equal(web3.utils.toHex(web3.utils.toBN(approvedSpending.data)), web3.utils.toHex(wantAmt));

        // Assert: farms token (wantLockedTotal incremented, farm's deposit() func called)
        assert.isTrue(web3.utils.toBN(depositedInFarm.topics[2]).eq(wantAmt));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance, router;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        router = setupObj.router;
    });

    it('unfarms Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(1e17)
        
        // Mint some tokens
        await router.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await router.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());
        // Simulate deposit
        await instance.depositWantToken(account, wantAmt);
        const wantLockedTotal = await instance.wantLockedTotal.call();

        // Unfarm
        const tx = await instance.unfarm(wantAmt);

        // Get logs
        const { rawLogs } = tx.receipt;
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: called unfarm() func
        assert.isTrue(web3.utils.toBN(unfarmed.topics[1]).eq(await instance.pid.call()));
        assert.isTrue(web3.utils.toBN(unfarmed.topics[2]).eq(wantAmt));

        // Assert wantLockedTotal updated
        assert.isTrue((await instance.wantLockedTotal.call()).isZero());
    });
});