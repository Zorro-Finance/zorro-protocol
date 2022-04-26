const MockVaultStargate = artifacts.require('MockVaultStargate');
const MockVaultFactoryStargate = artifacts.require('MockVaultFactoryStargate');
const zeroAddress = '0x0000000000000000000000000000000000000000';

contract('VaultFactoryStargate', async accounts => {
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
        tokenSTG: zeroAddress,
        stargatePoolId: 0
      };

    before(async () => {
        factory = await MockVaultFactoryStargate.deployed();
        instance = await MockVaultStargate.deployed();
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

contract('VaultStargate', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStargate.deployed();
    });

    xit('deposits Want token', async () => {
        // check auth
    });

    xit('exchanges USD for Want token', async () => {
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

    xit('farms Want token', async () => {
        // Check auth
    });

    xit('unfarms Want token', async () => {
        // Check auth
    });
});