const MockVaultAcryptosSingle = artifacts.require('MockVaultAcryptosSingle');
const MockVaultFactoryAcryptosSingle = artifacts.require('MockVaultFactoryAcryptosSingle');
const zeroAddress = '0x0000000000000000000000000000000000000000';

const MockAcryptosFarm = artifacts.require('MockAcryptosFarm');
const MockAcryptosVault = artifacts.require('MockAcryptosVault');
const MockBalancerVault = artifacts.require('MockBalancerVault');
const MockVaultZorro = artifacts.require("MockVaultZorro");
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockUSDC = artifacts.require('MockUSDC');
const MockBUSD = artifacts.require('MockBUSD');
const MockACS = artifacts.require('MockACS');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
const MockAMMToken0 = artifacts.require('MockAMMToken0');
const MockPriceAggToken0 = artifacts.require('MockPriceAggToken0');
const MockPriceAggEarnToken = artifacts.require('MockPriceAggEarnToken');
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');

const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(uint256,uint256)');
const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
const approvalEventSig = web3.eth.abi.encodeEventSignature('Approval(address,address,uint256)');
const swappedEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const addedLiqEventSig = web3.eth.abi.encodeEventSignature('AddedLiquidity(uint256,uint256,uint256)');
const removedLiqEventSig = web3.eth.abi.encodeEventSignature('RemovedLiquidity(uint256,uint256)');
const buybackEventSig = web3.eth.abi.encodeEventSignature('Buyback(uint256)');
const revShareEventSig = web3.eth.abi.encodeEventSignature('RevShare(uint256)');

const setupContracts = async (accounts) => {
    // Router
    const router = await MockAMMRouter02.deployed();
    await router.setBurnAddress(accounts[4]);
    // USDC
    const usdc = await MockUSDC.deployed();
    const busd = await MockBUSD.deployed();
    // Tokens
    const token0 = await MockAMMToken0.deployed();
    const acs = await MockACS.deployed();
    const ZORToken = await MockZorroToken.deployed();
    const ZORLPPoolOtherToken = await MockAMMOtherLPToken.deployed();
    // LP
    const acsVault = await MockAcryptosVault.deployed();
    // Swaps
    const balancerVault = await MockBalancerVault.deployed();
    await balancerVault.setBurnAddress(accounts[4]);
    // Farm contract
    const farmContract = await MockAcryptosFarm.deployed();
    await farmContract.setWantAddress(acsVault.address);
    await farmContract.setBurnAddress(accounts[4]);
    // Vault
    const zorroStakingVault = await MockVaultZorro.deployed();
    const instance = await MockVaultAcryptosSingle.deployed();
    await instance.setWantAddress(acsVault.address);
    await instance.setPoolAddress(acsVault.address); // IAcryptosVault (for entering strategy)
    await instance.setBalancerVaultAddress(balancerVault.address); // IBalancerVault (router for swaps)
    await instance.setFarmContractAddress(farmContract.address); // IAcryptosFarm (for farming want token)
    await instance.setZorroStakingVault(zorroStakingVault.address);
    await instance.setEarnedAddress(acs.address);
    await instance.setRewardsAddress(accounts[3]);
    await instance.setBurnAddress(accounts[4]);
    await instance.setUniRouterAddress(router.address);
    await instance.setToken0Address(token0.address);
    await instance.setTokenUSDCAddress(usdc.address);
    await instance.setBUSD(busd.address);
    await instance.setACS(acs.address);
    await instance.setZORROAddress(ZORToken.address);
    await instance.setZorroLPPoolOtherToken(ZORLPPoolOtherToken.address);
    // Set controller
    await instance.setZorroControllerAddress(accounts[0]);
    // Price feeds
    const token0PriceFeed = await MockPriceAggToken0.deployed();
    const earnTokenPriceFeed = await MockPriceAggEarnToken.deployed();
    const ZORPriceFeed = await MockPriceAggZOR.deployed();
    const lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
    await instance.setPriceFeed(0, token0PriceFeed.address);
    await instance.setPriceFeed(2, earnTokenPriceFeed.address);
    await instance.setPriceFeed(3, ZORPriceFeed.address);
    await instance.setPriceFeed(4, lpPoolOtherTokenPriceFeed.address);
    // Swap paths
    await instance.setSwapPaths(0, [usdc.address, token0.address]);
    await instance.setSwapPaths(2, [token0.address, usdc.address]);
    await instance.setSwapPaths(4, [farmContract.address, token0.address]);
    await instance.setSwapPaths(6, [farmContract.address, ZORToken.address]);
    await instance.setSwapPaths(7, [farmContract.address, ZORLPPoolOtherToken.address]);
    await instance.setSwapPaths(8, [farmContract.address, usdc.address]);
    await instance.setBUSDSwapPaths(0, [busd.address, token0.address]);
    await instance.setBUSDSwapPaths(1, [busd.address, ZORToken.address]);
    await instance.setBUSDSwapPaths(2, [busd.address, ZORLPPoolOtherToken.address]);

    return {
        instance,
        acsVault,
        farmContract,
        usdc,
        busd,
        acs,
        token0,
        ZORToken,
        zorroStakingVault,
    };
}

contract('VaultFactoryAcryptosSingle', async accounts => {
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
        USDCToToken0Path: [],
        earnedToZORLPPoolOtherTokenPath: [],
        earnedToUSDCPath: [],
        BUSDToToken0Path: [],
        BUSDToZORROPath: [],
        BUSDToLPPoolOtherTokenPath: [],
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
        factory = await MockVaultFactoryAcryptosSingle.deployed();
        instance = await MockVaultAcryptosSingle.deployed();
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

contract('VaultAcryptosSingle', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultAcryptosSingle.deployed();
    });

    it('sets Balancer pool weights', async () => {
        // Normal
        const acsWeight = 7000;
        const busdWeight = 7000;
        await instance.setBalancerWeights(acsWeight, busdWeight);

        assert.equal(await instance.balancerACSWeightBasisPoints.call(), acsWeight);
        assert.equal(await instance.balancerBUSDWeightBasisPoints.call(), busdWeight);

        // Only by owner
        try {
            await instance.setBalancerWeights(0, 0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets BUSD swap paths', async () => {
        // Normal
        const BUSD = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const AVAX = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const token0 = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        let path;
        // Set BUSDToToken0Path
        path = [BUSD, AVAX, token0];
        await instance.setBUSDSwapPaths(0, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.BUSDToToken0Path.call(i)), path[i]);
        }
        // Set BUSDToZORROPath
        path = [BUSD, token0, ZOR];
        await instance.setBUSDSwapPaths(1, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.BUSDToZORROPath.call(i)), path[i]);
        }
        // Set BUSDToLPPoolOtherTokenPath
        path = [BUSD, token0, otherToken];
        await instance.setBUSDSwapPaths(2, path);
        for (let i=0; i < 3; i++) {
            assert.equal(web3.utils.toChecksumAddress(await instance.BUSDToLPPoolOtherTokenPath.call(i)), path[i]);
        }


        // Only by owner
        try {
            await instance.setBUSDSwapPaths(0, [], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets BUSD', async () => {
        // Set
        const BUSD = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setBUSD(BUSD);
        assert.equal(await instance.tokenBUSD.call(), BUSD);

        // Only by owner
        try {
            await instance.setBUSD(BUSD, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets ACS', async () => {
        // Set
        const ACS = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setACS(ACS);
        assert.equal(await instance.tokenACS.call(), ACS);

        // Only by owner
        try {
            await instance.setACS(ACS, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Balancer Pool', async () => {
        // Set
        const balancerPool = web3.utils.randomHex(32);
        await instance.setBalancerPool(balancerPool);
        assert.equal(await instance.balancerPool.call(), balancerPool);

        // Only by owner
        try {
            await instance.setBalancerPool(balancerPool, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Balancer Vault', async () => {
        // Set
        const balancerVaultAddress = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setBalancerVaultAddress(balancerVaultAddress);
        assert.equal(await instance.balancerVaultAddress.call(), balancerVaultAddress);

        // Only by owner
        try {
            await instance.setBalancerVaultAddress(balancerVaultAddress, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('VaultAcryptosSingle', async accounts => {
    let instance, acsVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        acsVault = setupObj.acsVault;
    });

    it('deposits Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(accounts[0], 0);
        } catch (err) {
            assert.include(err.message, 'Want token deposit must be > 0');
        }

        // Mint some tokens
        await acsVault.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await acsVault.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

        /* First deposit */
        // Deposit
        const tx = await instance.depositWantToken(accounts[0], wantAmt);

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
        assert.isTrue((await instance.userShares.call(accounts[0])).eq(wantAmt));

        // Assert: calls farm()
        assert.isNotNull(farmed);

        /* Next deposit */
        // Set fees
        await instance.setFeeSettings(
            9990, // 0.1% deposit fee
            10000,
            0,
            0,
            0
        );
        // Deposit
        await instance.depositWantToken(accounts[0], wantAmt);

        // Assert: returns correct shares added (based on current shares etc.)
        const sharesTotal = wantAmt; // Total shares before second deposit
        const wantLockedTotal = wantAmt; // Total want locked before second deposit
        const sharesAdded = wantAmt.mul(sharesTotal).mul(web3.utils.toBN(9990)).div(wantLockedTotal.mul(web3.utils.toBN(10000)));
        const newTotalShares = web3.utils.toBN(sharesAdded).add(wantAmt);
        assert.isTrue((await instance.sharesTotal.call()).eq(newTotalShares));
        assert.isTrue((await instance.userShares.call(accounts[0])).eq(newTotalShares));

        /* Only Zorro controller */
        try {
            await instance.depositWantToken(zeroAddress, 0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }

    });
    it('withdraws Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentUserShares = await instance.userShares.call(accounts[0]);
        const currentWantLockedTotal = await instance.wantLockedTotal.call();

        /* Withdraw 0 */
        try {
            await instance.withdrawWantToken(accounts[0], 0); 
        } catch (err) {
            assert.include(err.message, 'want amt <= 0');
        }
        
        /* Withdraw > 0 */
        
        // Withdraw
        const tx = await instance.withdrawWantToken(accounts[0], wantAmt); 

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
        assert.isTrue((await instance.userShares.call(accounts[0])).eq(expectedUserShares));

        // Assert: calls unfarm()
        assert.isNotNull(unfarmed);

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));
    });

    it('withdraws safely when excess Want token specified', async () => {
        // Prep
        const currentWantLockedTotal = await instance.wantLockedTotal.call();
        const wantAmt = currentWantLockedTotal.add(web3.utils.toBN(1e12)); // Set to exceed the tokens locked, intentionally

        /* Withdraw > wantToken */

        // Withdraw
        const tx = await instance.withdrawWantToken(accounts[0], wantAmt); 

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
        assert.isTrue((await instance.userShares.call(accounts[0])).isZero());

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(currentWantLockedTotal));
    });
});

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('exchanges USD for Want token', async () => {
//         // Check auth
//     });

// });

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('selectively swaps based on token type', async () => {
//         // _safeSwap()
//         // Check auth
//     });

// });

contract('VaultAcryptosSingle', async accounts => {
    let instance, acsVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        acsVault = setupObj.acsVault;
    });

    xit('farms Want token', async () => {
        // Mint tokens
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.628', 'ether'));
        await lpPool.mint(instance.address, wantAmt);
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

contract('VaultAcryptosSingle', async accounts => {
    let instance, acsVault;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        acsVault = setupObj.acsVault;
    });

    xit('unfarms Earn token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(1e17)
        
        // Mint some tokens
        await lpPool.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await lpPool.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());
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

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('exchanges Want token for USD', async () => {
//         // Check auth
//     });

// });

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('auto compounds and earns', async () => {
//         // Check auth
//     });

// });

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('buys back Earn token, adds liquidity, and burns LP', async () => {
//         // Check auth
//     });

// });

// contract('VaultAcryptosSingle', async accounts => {
//     let instance, acsVault;

//     before(async () => {
//         const setupObj = await setupContracts(accounts);
//         instance = setupObj.instance;
//         acsVault = setupObj.acsVault;
//     });

//     xit('shares revenue with ZOR stakers', async () => {
//         // Check auth
//     });

// });

contract('VaultAcryptosSingle', async accounts => {
    let instance, acs;

    before(async () => {
        const setupObj = await setupContracts(accounts);
        instance = setupObj.instance;
        acs = setupObj.acs;
    });

    it('swaps Earn token to USD', async () => {
        /* Prep */
        const earnedAmt = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const rates = {
            earn: 1.2e12,
            ZOR: 1050,
            lpPoolOtherToken: 333,
        };
        // Send some Earn token
        await acs.mint(instance.address, earnedAmt);

        /* SwapEarnedToUSDC */
        // Swap
        const tx = await instance.swapEarnedToUSDC(
            earnedAmt,
            accounts[2],
            990,
            rates
        );

        // Logs
        const { rawLogs } = tx.receipt;

        let approvedSpending, swapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === approvalEventSig && !approvalEventSig && topics[2] === router.address && web3.utils.toBN(rl.data).eq(earnedAmt)) {
                approvedSpending = rl;
            } else if (topics[0] === swappedEventSig && topics[1] === accounts[2] && web3.utils.toBN(topics[2]).eq(earnedAmt)) {
                swapped = rl;
            }
        }

        // Assert: Approval
        assert.isNotNull(approvedSpending);
        // Assert: Swap
        assert.isNotNull(swapped);
    });
});