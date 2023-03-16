const { chains } = require("./constants");

const salt = () => web3.utils.numberToHex(Math.floor(4096*Math.random()));

const callTimelockFunc = async (timelock, callable, contractAddr) => {
    // Generate payload
    const payload = callable.encodeABI();

    const s = salt();

    // Schedule timelock
    await timelock.schedule(
        contractAddr,
        0,
        payload,
        '0x',
        s,
        0
    );

    // Execute timelock
    await timelock.execute(
        contractAddr,
        0,
        payload,
        '0x',
        s
    );
};

exports.callTimelockFunc = callTimelockFunc;

exports.setDeployerAsZC = async (vault, vaultTimelock, controller) => {
    await callTimelockFunc(vaultTimelock, vault.contract.methods.setContractAddress(12, controller), vault.address);
};

exports.setZorroControllerAsZC = async (vault, vaultTimelock, zc) => {
    await callTimelockFunc(vaultTimelock, vault.contract.methods.setContractAddress(12, zc.address), vault.address);
};

const now = () => Math.floor((new Date).getTime() / 1000);

const swapExactAVAXForTokens = async (router, path, dest, value) => {
    await router.swapExactAVAXForTokens(
        0,
        path,
        dest,
        now() + 300,
        { value }
    );
};

exports.swapExactAVAXForTokens = swapExactAVAXForTokens;

const swapExactETHForTokens = async (router, path, dest, value) => {
    await router.swapExactETHForTokens(
        0,
        path,
        dest,
        now() + 300,
        { value }
    );
};

exports.swapExactETHForTokens = swapExactETHForTokens;

exports.getUSDC = async (
    amountAvax,
    router,
    destination,
    web3
) => {
    // Get params
    const {wavax, usdc} = chains.avax.tokens;
    
    // Get USDC
    await swapExactAVAXForTokens(router, [wavax, usdc], destination, amountAvax);
};

exports.get_TJ_AVAX_USDC_LP = async (
    amountAvax, // as BN
    usdcERC20,
    iAVAX,
    router,
    destination,
    web3
) => {
    // Get params
    const {wavax, usdc} = chains.avax.tokens;

    // Wrap AVAX
    await iAVAX.deposit({ value: amountAvax });

    // Get exchg rate
    const exchNumer = (await router.getAmountsOut.call(
        web3.utils.toWei('1', 'ether'),
        [wavax, usdc]
    ))[1];
    const exchDenom = web3.utils.toBN(1e18);

    // Get LP token
    const amountUSDC = amountAvax.mul(exchNumer).div(exchDenom);
    await iAVAX.approve(router.address, amountAvax);
    await usdcERC20.approve(router.address, amountUSDC);
    console.log('amountAvax: ', amountAvax.toString(), 'amountUSDC: ', amountUSDC.toString());
    await router.addLiquidity(
        wavax,
        usdc,
        amountAvax,
        amountUSDC,
        0,
        0,
        destination,
        now() + 300
    );
};