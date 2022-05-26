const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockUSDC = artifacts.require('MockUSDC');

const receiveXChainDepositEventSig = web3.eth.abi.encodeEventSignature('ReceiveXChainDepositReq(uint256,uint256,address)');
const receiveXChainRepatriationEventSig = web3.eth.abi.encodeEventSignature('ReceiveXChainRepatriationReq(uint256,uint256,uint256)');
const receiveXChainDistributionEventSig = web3.eth.abi.encodeEventSignature('ReceiveXChainDistributionReq(uint256,uint256,uint256)');
const receiveXChainWithdrawalEventSig = web3.eth.abi.encodeEventSignature('ReceiveXChainWithdrawalReq(uint256,uint256,uint256)');

contract('ZorroController', async accounts => {
    let instance, usdc;

    before(async () => {
        instance = await MockZorroControllerXChain.deployed();
        usdc = await MockUSDC.deployed();
    });

    it('only allows registered x chain controller caller for Stargate', async () => {
        // Prep
        const srcAddress = web3.utils.hexToBytes(web3.utils.randomHex(30)); // 30 bytes to make it completely arbitrary
        const amount = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const payload = 'abc';
        // Run
        try {
            await instance.sgReceive(
                0,
                srcAddress,
                0,
                usdc.address,
                amount,
                payload
            );
        } catch (err) {
            // Test
            assert.include(err.message, 'Unrecog xchain controller');
        }
    });

    it('only allows registered x chain controller caller for LayerZero', async () => {
        // Prep
        const srcAddress = web3.utils.hexToBytes(web3.utils.randomHex(30)); // 30 bytes to make it completely arbitrary
        const payload = 'abc';
        // Run
        try {
            await instance.lzReceive(
                0,
                srcAddress,
                0,
                payload
            );
        } catch (err) {
            // Test
            assert.include(err.message, 'Unrecog xchain controller');
        }
    });
});
    
contract('ZorroController', async accounts => {
    let instance, usdc;

    before(async () => {
        // Instantiate
        instance = await MockZorroControllerXChain.deployed();
        usdc = await MockUSDC.deployed();

        // Set controller for chain 0 as current account
        const controller = web3.utils.hexToBytes(accounts[0]);
        await instance.setControllerContract(0, controller);
    });

    it('accepts Stargate :: receive X Chain deposit request', async () => {
        // Prep
        const pid = 0;
        const maxMarketMovement = 990;
        const weeksCommiteed = 4;
        const amountUSDCBeforeBridge = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const amountUSDCAfterBridge = amountUSDCBeforeBridge.mul(web3.utils.toBN(maxMarketMovement)).div(web3.utils.toBN(1000));
        const originAccount = web3.utils.hexToBytes(accounts[0]);
        const destAccount = web3.utils.randomHex(20); // Made up account

        const payload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainDepositRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_pid'},
                {type: 'uint256', name: '_valueUSDC'},
                {type: 'uint256', name: '_weeksComitted'},
                {type: 'uint256', name: '_maxmarketMovement'},
                {type: 'bytes', name: '_originAccount'},
                {type: 'address', name: '_destAccount'},
            ],
        }, [
            pid, 
            amountUSDCBeforeBridge,
            weeksCommiteed,
            maxMarketMovement,
            originAccount,
            destAccount
        ]);

        await usdc.mint(instance.address, amountUSDCAfterBridge);

        // Run
        const tx = await instance.sgReceive(
            0,
            originAccount,
            0,
            usdc.address,
            amountUSDCAfterBridge,
            payload
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let receiveDepositReq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === receiveXChainDepositEventSig) {
                receiveDepositReq = rl;
            }
        }

        // Test
        // PID 
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[1]).eq(web3.utils.toBN(pid)));
        // Value USDC
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[2]).eq(amountUSDCAfterBridge));
        // Dest account
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[3]).eq(web3.utils.toBN(destAccount)));
    });

    it('accepts Stargate :: receive X Chain repatriation request', async () => {
        // Prep
        const pid = 0;
        const originChainId = 0;
        const trancheId = 0;
        const originAccount = web3.utils.hexToBytes(accounts[0]);
        const originRecipient = web3.utils.hexToBytes(accounts[1]);
        const amountUSDC = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const rewardsDue = web3.utils.toBN(web3.utils.toWei('3.2', 'ether'));

        const payload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainRepatriationRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_originChainId'},
                {type: 'uint256', name: '_pid'},
                {type: 'uint256', name: '_trancheId'},
                {type: 'bytes', name: '_originRecipient'},
                {type: 'uint256', name: '_rewardsDue'},
            ],
        }, [
            originChainId,
            pid, 
            trancheId,
            originRecipient,
            rewardsDue,
        ]);

        await usdc.mint(instance.address, amountUSDC);

        // Run
        const tx = await instance.sgReceive(
            0,
            originAccount,
            0,
            usdc.address,
            amountUSDC,
            payload
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let receiveRepatriationReq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === receiveXChainRepatriationEventSig) {
                receiveRepatriationReq = rl;
            }
        }

        // Test
        // Origin chain ID 
        assert.isTrue(web3.utils.toBN(receiveRepatriationReq.topics[1]).eq(web3.utils.toBN(originChainId)));
        // Rewards due
        assert.isTrue(web3.utils.toBN(receiveRepatriationReq.topics[3]).eq(rewardsDue));
    });

    it('accepts Stargate :: receive X Chain distribution request', async () => {
        // Prep
        const remoteChainId = 1;
        const amountUSDC = web3.utils.toBN(web3.utils.toWei('200', 'ether'));
        const amountUSDCBuyback = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const amountUSDCRevShare = web3.utils.toBN(web3.utils.toWei('58', 'ether'));
        const accSlashedRewards = web3.utils.toBN(web3.utils.toWei('58', 'ether'));
        const maxMarketMovement = web3.utils.toBN(990);
        const originAccount = web3.utils.hexToBytes(accounts[0]);

        const payload = web3.eth.abi.encodeFunctionCall({
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

        await usdc.mint(instance.address, amountUSDC);

        // Run
        const tx = await instance.sgReceive(
            0,
            originAccount,
            0,
            usdc.address,
            amountUSDC,
            payload
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let receiveDistReq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === receiveXChainDistributionEventSig) {
                receiveDistReq = rl;
            }
        }

        // Test
        // USDC buyback 
        assert.isTrue(web3.utils.toBN(receiveDistReq.topics[1]).eq(amountUSDCBuyback));
        // USDC revshare
        assert.isTrue(web3.utils.toBN(receiveDistReq.topics[2]).eq(amountUSDCRevShare));
        // slashed rewards
        assert.isTrue(web3.utils.toBN(receiveDistReq.topics[3]).eq(accSlashedRewards));
    });


    it('accepts LayerZero :: receive X Chain withdrawal request', async () => {
        // Prep
        const originChainId = 1;
        const originAccount = web3.utils.hexToBytes(accounts[0]);
        const pid = 0;
        const trancheId = 0;
        const maxMarketMovement = web3.utils.toBN(990);

        const payload = web3.eth.abi.encodeFunctionCall({
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
            maxMarketMovement
        ]);

        // Run
        const tx = await instance.lzReceive(
            0,
            originAccount,
            0,
            payload
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let receiveWithdrawalReq;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === receiveXChainWithdrawalEventSig) {
                receiveWithdrawalReq = rl;
            }
        }
    
        // Test
        // Origin chain ID
        assert.isTrue(web3.utils.toBN(receiveWithdrawalReq.topics[1]).eq(web3.utils.toBN(originChainId)));
        // PID
        assert.isTrue(web3.utils.toBN(receiveWithdrawalReq.topics[2]).eq(web3.utils.toBN(pid)));
        // Tranche ID
        assert.isTrue(web3.utils.toBN(receiveWithdrawalReq.topics[3]).eq(web3.utils.toBN(trancheId)));
    });
})