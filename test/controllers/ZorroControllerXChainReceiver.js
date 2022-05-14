const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockUSDC = artifacts.require('MockUSDC');

const receiveXChainDepositEventSig = web3.eth.abi.encodeEventSignature('ReceiveXChainDepositReq(uint256,uint256,address)');

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
        
        console.log('current acct: ', accounts[0]);
        console.log('payload: ', payload);

        const decodedPayload = web3.eth.abi.decodeParameters([
            'uint256',
            'uint256',
            'uint256',
            'uint256',
            'bytes',
            'address',
        ], payload.slice(10)); // Remove first 4 bytes + '0x' prefix

        console.log('decoded payload: ', decodedPayload);

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
        console.log('receiveddr: ', receiveDepositReq);
        // Test
        // PID 
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[1]).eq(web3.utils.toBN(pid)));
        // Value USDC
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[2]).eq(amountUSDCAfterBridge));
        // Dest account
        assert.isTrue(web3.utils.toBN(receiveDepositReq.topics[3]).eq(web3.utils.toBN(destAccount)));
    });

    xit('accepts Stargate :: receive X Chain repatriation request', async () => {
        // Prep

        // Run

        // Test
    });

    xit('accepts Stargate :: receive X Chain distribution request', async () => {
        // Prep

        // Run

        // Test
    });


    xit('accepts LayerZero :: receive X Chain withdrawal request', async () => {
        // Prep

        // Run

        // Test
    });
})