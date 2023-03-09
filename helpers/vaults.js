const salt = web3.utils.numberToHex(4096);

exports.setDeployerAsZC = async (vault, vaultTimelock, controller) => {
    // Generate payload
    const payload = vault.contract.methods.setContractAddress(12, controller).encodeABI();

    // Schedule timelock
    await vaultTimelock.schedule(
        vault.address,
        0,
        payload,
        '0x',
        salt,
        0
    );

    // Execute timelock
    await vaultTimelock.execute(
        vault.address,
        0,
        payload,
        '0x',
        salt
    );
};

exports.setZorroControllerAsZC = async (vault, vaultTimelock, zc) => {
    // Generate payload
    const payload = vault.contract.methods.setContractAddress(12, zc.address).encodeABI();

    // Schedule timelock
    await vaultTimelock.schedule(
        vault.address,
        0,
        payload,
        '0x',
        salt,
        0
    );

    // Execute timelock
    await vaultTimelock.execute(
        vault.address,
        0,
        payload,
        '0x',
        salt
    );
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