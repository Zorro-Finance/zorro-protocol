const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockZorroController = artifacts.require('MockZorroController');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockStargateRouter = artifacts.require('MockStargateRouter');
const MockLayerZeroEndpoint = artifacts.require('MockLayerZeroEndpoint');

const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const stargateSwapEventSig = web3.eth.abi.encodeEventSignature('StargateSwap(address,address,uint256)');
const lzSentEventSig = web3.eth.abi.encodeEventSignature('SentMessage(uint16,uint256)');

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
        
        // Run
        const res = await instance.getLZAdapterParamsForWithdraw.call(gas);

        // Test
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedRes)));
    });

    it('checks X chain Repatriation fee', async () => {
        // Prep
        const burnableRewards = web3.utils.toBN(web3.utils.toWei('2.7', 'ether'));
        const rewardsDue = web3.utils.toBN(web3.utils.toWei('3.4', 'ether'));
        const originRecipient = web3.utils.hexToBytes(accounts[1]);
        // Run
        const repatriationFee = await instance.checkXChainRepatriationFee.call(
            0,
            0,
            0,
            originRecipient,
            burnableRewards,
            rewardsDue
        );

        // Assertions
        const expectedRepatriationFee = web3.utils.toBN(web3.utils.toWei('0.01', 'ether')); // Hardcoded
        assert.isTrue(repatriationFee.eq(expectedRepatriationFee));    
    });

    it('encodes X chain withdrawal payload', async () => {
        // Prep
        const originChainId = 0;
        const originAccount = web3.utils.hexToBytes(accounts[0]);
        const pid = 0;
        const trancheId = 0;
        const maxMarketMovement = 990;

        // Run
        const res = await instance.encodeXChainWithdrawalPayload.call(
            originChainId,
            originAccount,
            pid,
            trancheId,
            maxMarketMovement
        );

        // Test
        const expectedPayload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainWithdrawalRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_originChainId'},
                {type: 'bytes', name: '_originAccount'},
                {type: 'uint256', name: '_pid'},
                {type: 'uint256', name: '_trancheId'},
                {type: 'uint256', name: '_maxMarketMovement'},
            ],
        }, [
            originChainId,
            originAccount,
            pid,
            trancheId,
            maxMarketMovement,
        ]);
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedPayload)));    
    });

    it('encodes X chain repatriation payload', async () => {
        // Prep
        const originChainId = 0;
        const pid = 0;
        const trancheId = 0;
        const originRecipient = web3.utils.hexToBytes(accounts[1]);
        const burnableRewards = web3.utils.toBN(web3.utils.toWei('2.7', 'ether'));
        const rewardsDue = web3.utils.toBN(web3.utils.toWei('3.4', 'ether'));

        // Run
        const res = await instance.encodeXChainRepatriationPayload.call(
            originChainId,
            pid,
            trancheId,
            originRecipient,
            burnableRewards,
            rewardsDue
        );

        // Test
        const expectedPayload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainRepatriationRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_originChainId'},
                {type: 'uint256', name: '_pid'},
                {type: 'uint256', name: '_trancheId'},
                {type: 'bytes', name: '_originRecipient'},
                {type: 'uint256', name: '_burnableZORRewards'},
                {type: 'uint256', name: '_rewardsDue'},
            ],
        }, [
            originChainId,
            pid,
            trancheId,
            originRecipient,
            burnableRewards,
            rewardsDue,
        ]);
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedPayload)));        
    });

    it('sends X chain withdrawal request', async () => {
        // Prep
        const destZorroChainId = 0;
        const pid = 0;
        const trancheId = 0;
        const maxMarketMovement = 990;
        const gasFee = web3.utils.toBN(web3.utils.toWei('0.05', 'ether'));

        // Run
        const tx = await instance.sendXChainWithdrawalRequest(
            destZorroChainId,
            pid,
            trancheId,
            maxMarketMovement,
            gasFee,
            {value: gasFee}
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let lzSent;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === lzSentEventSig && web3.utils.toBN(topics[2]).eq(gasFee)) {
                lzSent = rl;
            }
        }

        // Test

        // Assert LZ send occurred and with correct value
        assert.isNotNull(lzSent);
    });

    it('sends X chain repatriation request', async () => {
        // Prep
        const originChainId = 0;
        const pid = 0;
        const trancheId = 0;
        const originRecipient = web3.utils.hexToBytes(accounts[1]);
        const maxMarketMovementAllowed = 990;
        const amountUSDC = web3.utils.toBN(web3.utils.toWei('200', 'ether'));
        const netAmountUSDC = amountUSDC.mul(web3.utils.toBN(maxMarketMovementAllowed)).div(web3.utils.toBN(1000));
        const burnableRewards = web3.utils.toBN(web3.utils.toWei('2.7', 'ether'));
        const rewardsDue = web3.utils.toBN(web3.utils.toWei('3.4', 'ether'));
        const gasFee = web3.utils.toBN(web3.utils.toWei('0.05', 'ether'));

        // Mint some usdc and approve
        await usdc.mint(instance.address, amountUSDC);
        // await usdc.approve(instance.address, amountUSDC);

        // Run
        const tx = await instance.sendXChainRepatriationRequest(
            originChainId,
            pid,
            trancheId,
            originRecipient,
            amountUSDC,
            burnableRewards,
            rewardsDue,
            maxMarketMovementAllowed,
            {value: gasFee}
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred, sgSwapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred && topics[2] === instance.address && web3.utils.toBN(rl.data).eq(amountUSDC)) {
                transferred = rl;
            } else if (topics[0] === stargateSwapEventSig && web3.utils.toBN(topics[2]).eq(netAmountUSDC)) {
                sgSwapped = rl;
            }
        }

        // Test

        // Assert transferred USDC
        assert.isNotNull(transferred);

        // Assert StargateSwap occurred
        assert.isNotNull(sgSwapped);
    });

    xit('receives X chain withdrawal request', async () => {
        // Prep

        // Run
        // const tx = await instance.mockReceiveXChainWithdrawalRequest(
        //     originChainId,
        //     originAccount,
        //     pid,
        //     trancheId,
        //     maxMarketMovement
        // );

        // Logs

        // Test
    });

    xit('receives X chain repatriation request', async () => {
        // Check auth
    });
});