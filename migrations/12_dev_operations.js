// Imports 
const { getKeyParams, getSynthNetwork } = require('../chains');

// Contracts
const Migrations = artifacts.require("Migrations");
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
const TraderJoe_WAVAX_USDC = artifacts.require("TraderJoe_WAVAX_USDC");
const VaultZorro = artifacts.require("VaultZorro");
const StargateUSDCOnAVAX = artifacts.require("StargateUSDCOnAVAX");
const IJoeRouter02 = artifacts.require("IJoeRouter02");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");
const IERC20 = artifacts.require("IERC20");
const IUniswapV2Factory = artifacts.require("IUniswapV2Factory");
const IStargateRouter = artifacts.require("IStargateRouter");

module.exports = async function (deployer, network, accounts) {
    // Web3
    const adapter = Migrations.interfaceAdapter;
    const { web3 } = adapter;

    
    if (network === 'avaxfork') {
        // Deployed contracts
        const vaultZorro = await VaultZorro.deployed();
        const zorroController = await ZorroController.deployed();
        const zorroControllerXChain = await ZorroControllerXChain.deployed();
        const zorro = await Zorro.deployed();
        const sgVault = await StargateUSDCOnAVAX.deployed();
        const vaultZorroAvax = await TraderJoe_ZOR_WAVAX.deployed();
        const vaultAvaxUSDC = await TraderJoe_WAVAX_USDC.deployed();
        // Prep
        const now = Math.floor((new Date).getTime() / 1000);
        const wavax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';
        const usdc = '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E';
        // Hardcoded addresses used for testing
        const recipient0 = '0x92F0bf71c624FA6E99682bd3FBc8370cc0F366Ae';
        const recipient1 = '0xC5faECaA3d71EF9Ec13cDA5eFfc9ba5C53a823Fe';

        // Iterate
        const recipients = [recipient0, recipient1, accounts[0]];
        console.log('Distributing tokens to recipients: ', recipients)
        for (let recipient of recipients) {
            console.log('Current recipient: ', recipient);

            // Transfer AVAX to designated wallets
            const value = web3.utils.toWei('100000', 'ether');
            await web3.eth.sendTransaction({from: accounts[0], to: recipient, value});
    
            // Mint ZOR to designated wallets
            await zorro.setZorroController(accounts[0]);
            await zorro.mint(recipient, web3.utils.toWei('100', 'ether'));
            await zorro.setZorroController(zorroController.address);
            console.log('minted ZOR');

            // Swap USDC to designated wallets
            const router = await IJoeRouter02.at('0x60aE616a2155Ee3d9A68541Ba4544862310933d4');
            await router.swapExactAVAXForTokens(
                0,
                [wavax, usdc],
                recipient,
                now + 300,
                {value}
            );
            console.log('swapped USDC');

            // Send some JLP token
            const factory = await IUniswapV2Factory.at('0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10');
            const pairAddress = await factory.getPair(zorro.address, wavax);
            const jlp = await IERC20.at(pairAddress);
            const jlpBal = await jlp.balanceOf(accounts[0]);
            await jlp.transfer(recipient, jlpBal.mul(web3.utils.toBN(3)).div(web3.utils.toBN(10)));
            console.log('Sent JLP');

            // Send some SG LP token
            // const sgRouter = await IStargateRouter.at('0x45A01E4e04F14f7A4a6702c74187c5F6222033cd');
            // const defaultStablecoin = await IERC20.at(usdc);
            // console.log('usdc balance: ', (await defaultStablecoin.balanceOf.call(recipient)).toString());
            // await defaultStablecoin.approve(sgRouter.address, '500000000');
            // await sgRouter.addLiquidity(1, '500000000', recipient);
        }

        // Transfer ownership of all contracts
        const newOwner = recipient1;
        console.log('Setting ownership to: ', newOwner);
        console.log('zc');
        console.log('owner of zc: ', await zorroController.owner.call());
        await zorroController.setZorroControllerOracle(newOwner);
        await zorroController.transferOwnership(newOwner);
        console.log('zsv', await vaultZorro.owner.call(), await vaultZorro.govAddress.call());
        await vaultZorro.transferOwnership(newOwner);
        await vaultZorro.setGov(newOwner);
        console.log('VaultStargate', await sgVault.owner.call(), await vaultZorro.govAddress.call());
        await sgVault.transferOwnership(newOwner);
        await sgVault.setGov(newOwner);
        console.log('VaultZorAvax', await vaultZorroAvax.owner.call(), await vaultZorroAvax.govAddress.call());
        await vaultZorroAvax.transferOwnership(newOwner);
        await vaultZorroAvax.setGov(newOwner);
        console.log('VaultAvaxUSDC', await vaultAvaxUSDC.owner.call(), await vaultAvaxUSDC.govAddress.call());
        await vaultAvaxUSDC.transferOwnership(newOwner);
        await vaultAvaxUSDC.setGov(newOwner);
    }

    if (network === 'bscfork') {
        // TODO
    }
};