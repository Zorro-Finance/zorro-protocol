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

exports.swapExactAVAXForTokens = async (router, path, dest, value) => {
    await router.swapExactAVAXForTokens(
        0,
        path,
        dest,
        now() + 300,
        { value }
    );
};

exports.swapExactETHForTokens = async (router, path, dest, value) => {
    await router.swapExactETHForTokens(
        0,
        path,
        dest,
        now() + 300,
        { value }
    );
};