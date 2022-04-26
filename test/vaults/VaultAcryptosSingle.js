const MockVaultAcryptosSingle = artifacts.require('MockVaultAcryptosSingle');
const MockVaultFactoryAcryptosSingle = artifacts.require('MockVaultFactoryAcryptosSingle');
const zeroAddress = '0x0000000000000000000000000000000000000000';

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

    xit('deposits Want token', async () => {
        // check auth
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