const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');
const MockVaultFactoryStandardAMM = artifacts.require('MockVaultFactoryStandardAMM');


contract('VaultFactoryStandardAMM', async accounts => {
    let factory;
    let instance;
    const zeroAddress = '0x0000000000000000000000000000000000000000';
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
        console.log('depl vault: ', await factory.deployedVaults.call(0));
        assert.isNotNull(await factory.deployedVaults.call(0));

        // Only owner
        try {
            await factory.createVault(accounts[0], initVal, {from: accounts[1]});
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance; 

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
    });

    xit('deposits Want token', async () => {
        // Prep
        const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const wantAmt = web3.utils.toWei('0.547', 'ether');

        // Make pre-deposit

        // Deposit (0)

        // Deposit (> 0)

        // Assert: transfers Want token

        // Assert: returns correct shares added

        // Assert: farms token (wantLockedTotal incremented, farm's deposit() func called)

        // Assert: does not farm token? 

        // Assert: increments shares (total shares and user shares)

        // Only owner
    });

    xit('exchanges USD for Want token', async () => {
        // Check auth
    });

    xit('selectively swaps based on token type', async () => {
        // _safeSwap()
        // Check auth
    });

    xit('farms Want token', async () => {
        // Check auth
    });

    xit('unfarms Earn token', async () => {
        // Check auth
    });

    xit('withdraws Want token', async () => {
        // Check auth
    });

    xit('exchanges Want token for USD', async () => {
        // Check auth
    });

    xit('auto compounds and earns', async () => {
        // Check auth
    });

    xit('buys back Earn token, adds liquidity, and burns LP', async () => {
        // Check auth
    });

    xit('shares revenue with ZOR stakers', async () => {
        // Check auth
    });

    xit('swaps Earn token to USD', async () => {
        // Check auth
    });
});