const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockZorroController = artifacts.require('MockZorroController');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockVaultZorro = artifacts.require('MockVaultZorro');
const MockAMMRouter02 = artifacts.require('MockAMMRouter02');
const MockAMMOtherLPToken = artifacts.require("MockAMMOtherLPToken");
const MockPriceAggZOR = artifacts.require('MockPriceAggZOR');
const MockPriceAggLPOtherToken = artifacts.require('MockPriceAggLPOtherToken');

const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const stargateSwapEventSig = web3.eth.abi.encodeEventSignature('StargateSwap(address,address,uint256)');
const swappedEventSig = web3.eth.abi.encodeEventSignature('SwappedToken(address,uint256,uint256)');
const addedLiqEventSig = web3.eth.abi.encodeEventSignature('AddedLiquidity(uint256,uint256,uint256)');

contract('ZorroControllerXChainEarn', async accounts => {
    let instance, controller, usdc, sgRouter, ZORToken, ZORStakingVault;
    let router, ZORLPPoolOtherToken, ZORPriceFeed, lpPoolOtherTokenPriceFeed;

    before(async () => {
        // Constants
        const burnAddress = accounts[4];
        // Instantiate contracts
        instance = await MockZorroControllerXChain.deployed();
        controller = await MockZorroController.deployed();
        usdc = await MockUSDC.deployed();
        router = await MockAMMRouter02.deployed();
        sgRouter = await MockStargateRouter.deployed();
        ZORToken = await MockZorroToken.deployed();
        ZORStakingVault = await MockVaultZorro.deployed();
        ZORLPPoolOtherToken = await MockAMMOtherLPToken.deployed();
        ZORPriceFeed = await MockPriceAggZOR.deployed();
        lpPoolOtherTokenPriceFeed = await MockPriceAggLPOtherToken.deployed();
        // Set X Chain controller
        const lzEndpoint = web3.utils.randomHex(20);
        const publicPool = web3.utils.randomHex(20);
        await instance.setLayerZeroParams(
            sgRouter.address,
            0,
            lzEndpoint
        );
        await instance.setTokens([
            usdc.address,
            ZORToken.address,
        ]);
        await instance.setZorroStakingVault(ZORStakingVault.address);
        await instance.setZorroLPPoolOtherToken(ZORLPPoolOtherToken.address);
        // Router
        await router.setBurnAddress(burnAddress);
        // Set controller to current account in order to make call
        const mockCtrl = accounts[0];
        await instance.setControllerContract(0, mockCtrl);
        await instance.setKeyContracts([
            mockCtrl,
            controller.address,
            publicPool
        ]);
        await instance.setUniRouterAddress(router.address);
        await instance.setSwapPaths(
            [usdc.address, ZORToken.address],
            [usdc.address, ZORLPPoolOtherToken.address]
        );
        await instance.setPriceFeeds([
            ZORPriceFeed.address,
            lpPoolOtherTokenPriceFeed.address,
        ]);
        await instance.setBurnAddress(burnAddress);
        // Set SG router
        await sgRouter.setBurnAddress(burnAddress);
        await sgRouter.setAsset(usdc.address);
        // Set controller
        await controller.setZorroXChainEndpoint(instance.address);
        await controller.add(
            0,
            web3.utils.randomHex(20),
            false,
            accounts[0] // Vault
        );
    });

    it('encodes x chain distribute earnings payload', async () => {
        // Prep
        const remoteChainId = 0;
        const amountUSDCBuyback = web3.utils.toBN(web3.utils.toWei('200', 'ether'));
        const amountUSDCRevShare = web3.utils.toBN(web3.utils.toWei('300', 'ether'));
        const accSlashedRewards = web3.utils.toBN(web3.utils.toWei('7', 'ether'));
        const maxMarketMovement = 990;

        // Run
        const res = await instance.encodeXChainDistributeEarningsPayload.call(
            remoteChainId,
            amountUSDCBuyback,
            amountUSDCRevShare,
            accSlashedRewards,
            maxMarketMovement
        );

        // Test
        const expectedPayload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainDistributionRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_remoteChainId'},
                {type: 'uint256', name: '_amountUSDCBuyback'},
                {type: 'uint256', name: '_amountUSDCRevShare'},
                {type: 'uint256', name: '_accSlashedRewards'},
                {type: 'uint256', name: '_maxMarketMovement'},
            ],
        }, [
            remoteChainId,
            amountUSDCBuyback,
            amountUSDCRevShare,
            accSlashedRewards,
            maxMarketMovement
        ]);
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedPayload)));
    });

    it('sends x chain dist earnings request', async () => {
        // Prep
        const pid = 0;
        const buybackAmountUSDC = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const revShareAmountUSDC = web3.utils.toBN(web3.utils.toWei('3', 'ether'));
        const totalDepositUSDC = buybackAmountUSDC.add(revShareAmountUSDC);
        const maxMarketMovement = 990;
        const netDepositUSDC = totalDepositUSDC.mul(web3.utils.toBN(maxMarketMovement)).div(web3.utils.toBN(1000));
        const gasFee = web3.utils.toBN(web3.utils.toWei('0.05', 'ether'));

        // Mint some usdc and approve
        await usdc.mint(accounts[0], totalDepositUSDC);
        await usdc.approve(instance.address, totalDepositUSDC);

        // Run
        const tx = await instance.sendXChainDistributeEarningsRequest(
            pid,
            buybackAmountUSDC,
            revShareAmountUSDC,
            maxMarketMovement,
            {value: gasFee}
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred, sgSwapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred && topics[2] === instance.address && web3.utils.toBN(rl.data).eq(totalDepositUSDC)) {
                transferred = rl;
            } else if (topics[0] === stargateSwapEventSig && web3.utils.toBN(topics[2]).eq(netDepositUSDC)) {
                sgSwapped = rl;
            }
        }

        // Test

        // Assert transferred USDC
        assert.isNotNull(transferred);

        // Assert StargateSwap occurred
        assert.isNotNull(sgSwapped);
    });

    it('buys back + LP + earn', async () => {
        // Prep
        const amountUSDC = web3.utils.toBN(web3.utils.toWei('300', 'ether'));
        const maxMarketMovement = 990;
        const burnAddress = accounts[4];

        // Mint some USDC to instance
        await usdc.mint(instance.address, amountUSDC);

        // Run
        console.log('instance addr: ', instance.address);
        console.log('router addr: ', router.address);
        console.log('usdc address: ', usdc.address);
        console.log('zor address: ', ZORToken.address);
        console.log('path0: ', await instance.USDCToZorroPath.call(0));
        console.log('path1: ', await instance.USDCToZorroPath.call(1));
        console.log('set router addr: ', await instance.uniRouterAddress.call());
        const tx = await instance.buybackOnChain(
            amountUSDC,
            maxMarketMovement
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred, addedLiq;
        let swapped = [];
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && topics[2] === burnAddress) {
                transferred = rl;
            } else if (topics[0] === swappedEventSig) {
                swapped.push(rl);
            } else if (topics[0] === addedLiqEventSig) {
                addedLiq = rl;
            }
        }

        // Tests

        // Swaps to ZOR, other LP token
        assert.equal(swapped.length, 2);
        // Adds liquidity
        assert.isNotNull(addedLiq);
        // Burns LP token
        assert.isNotNull(transferred);
    });

    xit('rev shares', async () => {

    });

    it('awards slashed rewards to stakers', async () => {
        // Prep 
        const slashedRewards = web3.utils.toBN(web3.utils.toWei('34.175', 'ether'));

        // Run
        const tx = await instance.awardSlashedRewardsToStakers(slashedRewards);

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred && topics[2] === ZORStakingVault.address && web3.utils.toBN(rl.data).eq(slashedRewards)) {
                transferred = rl;
            }
        }

        // Test
        // Assert transfer occurred
        assert.isNotNull(transferred);
    });
});

contract('ZorroControllerXChainEarn setters', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroControllerXChain.deployed();
    }); 

    it('sets Zorro LP Pool other token', async () => {
        // Normal
        const zorroLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroLPPoolOtherToken(zorroLPPoolOtherToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPoolOtherToken.call()), zorroLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setZorroLPPoolOtherToken(zorroLPPoolOtherToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro staking vault', async () => {
        // Normal
        const zorroStakingVault = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroStakingVault(zorroStakingVault);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroStakingVault.call()), zorroStakingVault);
        // Only by owner
        try {
            await instance.setZorroStakingVault(zorroStakingVault, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets uni router address', async () => {
        // Normal
        const uniRouterAddress = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUniRouterAddress(uniRouterAddress);
        assert.equal(web3.utils.toChecksumAddress(await instance.uniRouterAddress.call()), uniRouterAddress);
        // Only by owner
        try {
            await instance.setUniRouterAddress(uniRouterAddress, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets swap path', async () => {
         // Normal
         const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const AVAX = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         const otherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
         await instance.setSwapPaths([USDC, AVAX, ZOR], [USDC, otherToken]);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(0)), USDC);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(1)), AVAX);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(2)), ZOR);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(0)), USDC);
         assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(1)), otherToken);
         // Only by owner
         try {
             await instance.setSwapPaths([], [], { from: accounts[1] });
         } catch (err) {
             assert.include(err.message, 'caller is not the owner');
         }
    });
});