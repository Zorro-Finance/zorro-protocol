const MockZorroControllerXChain = artifacts.require('MockZorroControllerXChain');
const MockZorroController = artifacts.require('MockZorroController');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockStargateRouter = artifacts.require('MockStargateRouter');

const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const stargateSwapEventSig = web3.eth.abi.encodeEventSignature('StargateSwap(address,address,uint256)');

contract('ZorroControllerXChain', async accounts => {
    let instance, controller, usdc, sgRouter, ZORToken;

    before(async () => {
        // Constants
        const burnAddress = accounts[4];
        // Instantiate contracts
        instance = await MockZorroControllerXChain.deployed();
        controller = await MockZorroController.deployed();
        usdc = await MockUSDC.deployed();
        sgRouter = await MockStargateRouter.deployed();
        ZORToken = await MockZorroToken.deployed();
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

    it('checks X chain deposit fee', async () => {
        // Prep
        const depositUSDC = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const destContract = web3.utils.randomHex(20);
        const destWallet = web3.utils.randomHex(20);
        // Run
        const depositFee = await instance.checkXChainDepositFee.call(
            0,
            destContract,
            0,
            depositUSDC,
            4,
            990,
            destWallet
        );

        // Assertions
        const expectedDepositFee = web3.utils.toBN(web3.utils.toWei('0.01', 'ether')); // Hardcoded
        assert.isTrue(depositFee.eq(expectedDepositFee));
    });
    
    it('encodes x chain deposit payload', async () => {
        // Prep
        const depositUSDC = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const originWallet = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const destWallet = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

        // Run
        const res = await instance.encodeXChainDepositPayload.call(
            0,
            0,
            depositUSDC,
            4,
            990,
            originWallet,
            destWallet,
        );

        // Test
        const expectedPayload = web3.eth.abi.encodeFunctionCall({
            name: 'receiveXChainDepositRequest',
            type: 'function',
            inputs: [
                {type: 'uint256', name: '_pid'},
                {type: 'uint256', name: '_valueUSDC'},
                {type: 'uint256', name: '_weeksCommitted'},
                {type: 'uint256', name: '_maxMarketMovement'},
                {type: 'bytes', name: '_originAccount'},
                {type: 'address', name: '_destAccount'},
            ],
        }, [
            0,
            depositUSDC,
            4,
            990,
            originWallet,
            destWallet,
        ]);
        assert.isTrue(web3.utils.toBN(res).eq(web3.utils.toBN(expectedPayload)));
    });

    it('sends x chain deposit request', async () => {
        // Prep
        const depositUSDC = web3.utils.toBN(web3.utils.toWei('2', 'ether'));
        const netDepositUSDC = depositUSDC.mul(web3.utils.toBN(990)).div(web3.utils.toBN(1000));
        const destWallet = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const gasFee = web3.utils.toBN(web3.utils.toWei('0.05', 'ether'));

        // Mint some usdc and approve
        await usdc.mint(accounts[0], depositUSDC);
        await usdc.approve(instance.address, depositUSDC);

        // Run
        const tx = await instance.sendXChainDepositRequest(
            0,
            0,
            depositUSDC,
            4,
            990,
            destWallet,
            {value: gasFee}
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let transferred, sgSwapped;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred && topics[2] === instance.address && web3.utils.toBN(rl.data).eq(depositUSDC)) {
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
});