const MockVaultAcryptosSingle = artifacts.require('MockVaultAcryptosSingle');
const MockVaultFactoryAcryptosSingle = artifacts.require('MockVaultFactoryAcryptosSingle');
const zeroAddress = '0x0000000000000000000000000000000000000000';

const MockAcryptosFarm = artifacts.require('MockAcryptosFarm');
const MockVaultZorro = artifacts.require("MockVaultZorro");
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockUSDC = artifacts.require('MockUSDC');
const MockBUSD = artifacts.require('MockBUSD');
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
    const ZORToken = await MockZorroToken.deployed();
    const ZORLPPoolOtherToken = await MockAMMOtherLPToken.deployed();
    // Farm contract
    const farmContract = await MockAcryptosFarm.deployed();
    await farmContract.setWantAddress(lpPool.address);
    await farmContract.setBurnAddress(accounts[4]);
    // Vault
    const zorroStakingVault = await MockVaultZorro.deployed();
    const instance = await MockVaultStandardAMM.deployed();
    await instance.setWantAddress(lpPool.address);
    await instance.setPoolAddress(lpPool.address);
    await instance.setFarmContractAddress(farmContract.address);
    await instance.setZorroStakingVault(zorroStakingVault.address);
    await instance.setEarnedAddress(farmContract.address);
    await instance.setRewardsAddress(accounts[3]);
    await instance.setBurnAddress(accounts[4]);
    await instance.setUniRouterAddress(router.address);
    await instance.setToken0Address(token0.address);
    await instance.setTokenUSDCAddress(usdc.address);
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
        router,
        farmContract,
        usdc,
        busd,
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