const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockZorroController = artifacts.require('MockZorroController');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockLayerZeroEndpoint = artifacts.require('MockLayerZeroEndpoint');

const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const stargateSwapEventSig = web3.eth.abi.encodeEventSignature('StargateSwap(address,address,uint256)');

contract('ZorroControllerXChain', async accounts => {
    let instance, controller, usdc, sgRouter, lzEndpoint, ZORToken;

    before(async () => {
        // Constants
        const burnAddress = accounts[4];
        // Instantiate contracts
        instance = await MockZorroControllerXChain.deployed();
        controller = await MockZorroController.deployed();
        usdc = await MockUSDC.deployed();
        sgRouter = await MockStargateRouter.deployed();
        lzEndpoint = await MockLayerZeroEndpoint.deployed();
        ZORToken = await MockZorroToken.deployed();
        // Set X Chain controller
        const publicPool = web3.utils.randomHex(20);
        await instance.setLayerZeroParams(
            sgRouter.address,
            0,
            lzEndpoint.address,
        );
        await instance.setTokens([
            usdc.address,
            ZORToken.address,
        ]);
        // Set controller to current account in order to make call
        const mockCtrl = accounts[0];
        await instance.setControllerContract(0, mockCtrl);
        await instance.setKeyContracts([
            mockCtrl,
            controller.address,
            publicPool
        ]);
        // Set SG router
        await sgRouter.setBurnAddress(burnAddress);
        await sgRouter.setAsset(usdc.address);
        // Set controller
        await controller.setZorroXChainEndpoint(instance.address);
    });

    it('checks X chain withdrawal fee', async () => {
        // Prep
        const gasForDestinationLZReceive = web3.utils.toBN(web3.utils.toWei('0.0005', 'ether'));
        // Run
        const withdrawalFee = await instance.checkXChainWithdrawalFee.call(
            0,
            0,
            0,
            990,
            gasForDestinationLZReceive
        );

        // Assertions
        const expectedWithdrawalFee = web3.utils.toBN(web3.utils.toWei('0.1', 'ether')); // Hardcoded
        assert.isTrue(withdrawalFee.eq(expectedWithdrawalFee));
    });
    
    it('gets LZ adapter params', async () => {
        // Prep
        const gas = 200000;
        const expectedRes = '0x00010000000000000000000000000000000000000000000000000000000000030d40'
        console.log('exp res: ', expectedRes);
        
        // Run
        const res = await instance.getLZAdapterParamsForWithdraw.call(gas);

        // Test
        console.log('res: ', res);
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedRes)));
    });

    xit('checks X chain Repatriation fee', async () => {
        
    });

    xit('encodes X chain withdrawal payload', async () => {
        
    });

    xit('sends X chain withdrawal request', async () => {
        // Check auth
    });

    xit('sends X chain repatriation request', async () => {
        // Check auth
    });

    xit('receives X chain withdrawal request', async () => {
        // Check auth
    });

    xit('receives X chain repatriation request', async () => {
        // Check auth
    });
})