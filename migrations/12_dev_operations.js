// Imports 
const { getKeyParams, getSynthNetwork } = require('../chains');

// Contracts
const Migrations = artifacts.require("Migrations");
const TraderJoe_ZOR_WAVAX = artifacts.require("TraderJoe_ZOR_WAVAX");
const VaultZorro = artifacts.require("VaultZorro");
const VaultStargate = artifacts.require("VaultStargate");
const IJoeRouter02 = artifacts.require("IJoeRouter02");
const ZorroController = artifacts.require("ZorroController");
const ZorroControllerXChain = artifacts.require("ZorroControllerXChain");
const Zorro = artifacts.require("Zorro");

module.exports = async function (deployer, network, accounts) {
    // Web3
    const adapter = Migrations.interfaceAdapter;
    const { web3 } = adapter;

    // Deployed contracts
    const vaultZorro = await VaultZorro.deployed();
    const zorroController = await ZorroController.deployed();
    const zorroControllerXChain = await ZorroControllerXChain.deployed();
    const zorro = await Zorro.deployed();
    const vaultStargate = await VaultStargate.deployed();
    const vaultZorroAvax = await TraderJoe_ZOR_WAVAX.deployed();

    if (network === 'ganachecloud') {
        // Prep
        const now = Math.floor((new Date).getTime() / 1000);
        const wavax = '0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7';
        const usdc = '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E';
        // Hardcoded addresses used for testing
        const recipient0 = '0x92F0bf71c624FA6E99682bd3FBc8370cc0F366Ae';
        const recipient1 = '0xC5faECaA3d71EF9Ec13cDA5eFfc9ba5C53a823Fe';

        // Iterate
        for (let recipient of [recipient0, recipient1]) {
            // Transfer AVAX to designated wallets
            const value = web3.utils.toWei('1000', 'ether');
            await web3.eth.sendTransaction({from: accounts[0], to: recipient, value});
    
            // Mint ZOR to designated wallets
            await zorro.setZorroController(accounts[0]);
            await zorro.mint(recipient, web3.utils.toWei('100', 'ether'));
            await zorro.setZorroController(zorroController.address);

            // Swap USDC to designated wallets
            const router = await IJoeRouter02.at('0x60aE616a2155Ee3d9A68541Ba4544862310933d4');
            await router.swapExactAVAXForTokens(
                0,
                [wavax, usdc],
                recipient,
                now + 300,
                {value: web3.utils.toWei('1000', 'ether')}
            );
        }

        // Transfer ownership of all contracts
        const newOwner = recipient0;
        console.log('Setting ownership to: ', newOwner);
        console.log('zc');
        console.log('owner of zc: ', await zorroController.owner.call());
        await zorroController.transferOwnership(newOwner);
        console.log('zsv', await vaultZorro.owner.call(), await vaultZorro.govAddress.call());
        await vaultZorro.transferOwnership(newOwner);
        await vaultZorro.setGov(newOwner);
        console.log('VaultStargate', await vaultStargate.owner.call(), await vaultZorro.govAddress.call());
        await vaultStargate.transferOwnership(newOwner);
        await vaultStargate.setGov(newOwner);
        console.log('VaultZorAvax', await vaultZorroAvax.owner.call(), await vaultZorroAvax.govAddress.call());
        await vaultZorroAvax.transferOwnership(newOwner);
        await vaultZorroAvax.setGov(newOwner);
    }
};