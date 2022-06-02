const MockZorroController = artifacts.require('MockZorroController');
const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');

contract('ZorroController', async accounts => {
    let instance, vault;

    before(async () => {
        instance = await MockZorroController.deployed();
        vault = await MockVaultStandardAMM.deployed();
    });

    it('adds a pool', async () => {
        // Prep
        const allocPoint = web3.utils.toBN(100);
        const wantAddress = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        // Run 
        await instance.add(
            allocPoint,
            wantAddress,
            true,
            vault.address
        );
        const currBlock = await web3.eth.getBlockNumber();

        // Test
        const poolInfo = await instance.poolInfo.call(0);
        assert.equal(poolInfo.want, wantAddress);
        assert.isTrue(poolInfo.allocPoint.eq(allocPoint));
        assert.isTrue(poolInfo.lastRewardBlock.eq(web3.utils.toBN(currBlock)));
        assert.isTrue(poolInfo.accZORRORewards.isZero());
        assert.isTrue(poolInfo.totalTrancheContributions.isZero());
        assert.equal(poolInfo.vault, vault.address);

        // Only by owner
        try {
            await instance.add(allocPoint, wantAddress, true, vault.address, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('updates settings for a pool', async () => {
        // Prep
        const pid = 0;
        const newAllocPoint = web3.utils.toBN(150);

        // Run
        await instance.set(
            pid, 
            newAllocPoint,
            true
        );

        // Test
        const poolInfo = await instance.poolInfo.call(pid);
        const totalAllocPoint = await instance.totalAllocPoint.call();
        assert.isTrue(poolInfo.allocPoint.eq(newAllocPoint))
        assert.isTrue(totalAllocPoint.eq(newAllocPoint));


        // Only by owner
        try {
            await instance.set(pid, newAllocPoint, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('mass updates all pools', async () => {
        // Prep (none)

        // Run
        await instance.massUpdatePools();

        // Test
        const currBlock = await web3.eth.getBlockNumber();
        const poolInfo = await instance.poolInfo.call(0);
        assert.isTrue(poolInfo.lastRewardBlock.eq(web3.utils.toBN(currBlock)));
    });
})