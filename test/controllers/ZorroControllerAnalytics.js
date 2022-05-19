const MockZorroController = artifacts.require('MockZorroController');

const getInstance = async (accounts) => {
    // Get instance 
    const instance = await MockZorroController.deployed();

    // Set rewards params
    await instance.setRewardsParams(
        14400, // blocks per day
        [
            1, // Min daily dist points bp
            20, // Max daily dist points bp
        ],
        1, // Chain multiplier
        10 // Base reward rate bp
    );

    // Add pool
    await instance.add(
        1, // alloc point (multiplier)
        '0x0000000000000000000000000000000000000000',
        true,
        '0x0000000000000000000000000000000000000001'
    );
    console.log('block after adding pool: ', await web3.eth.getBlockNumber());

    // Set Zorro Oracle (to allow setting below)
    await instance.setZorroControllerOracle(accounts[0]);

    // Fill public pool

    // Set ZORROPerBlock
    await instance.setZorroPerBlock(
        web3.utils.toBN(1), // totalChainMultipliers
        web3.utils.toBN(10e9), // totalMarketTVLUSD
        web3.utils.toBN(5000), // _targetTVLCaptureBasisPoints
        web3.utils.toBN(1e6), // _ZorroTotalVaultTVLUSD
        web3.utils.toBN(web3.utils.toWei('800000', 'ether')) // _publicPoolZORBalance
    );
    console.log('blocksPerDay: ', (await instance.blocksPerDay.call()).toString());
    console.log('chainmultip: ', (await instance.chainMultiplier.call()).toString());
    console.log('bpmin: ', (await instance.ZORRODailyDistributionFactorBasisPointsMin.call()).toString());
    console.log('bpmax: ', (await instance.ZORRODailyDistributionFactorBasisPointsMax.call()).toString());
    console.log('baserewardratebp: ', (await instance.baseRewardRateBasisPoints.call()).toString());
    console.log('just set ZORPerBlock: ', (await instance.ZORROPerBlock.call()).toString());

    return instance;
};


contract('ZorroControllerAnalytics', async accounts => {
    let instance;

    before(async () => {
        instance = await getInstance(accounts);
    });

    it('should return 0 pending rewards for when the pool has no contributions', async () => {
        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[1],
            0 // trancheId
        );
        assert.equal(
            pendingRewards,
            0
        );
    });
});

contract('ZorroControllerAnalytics', async accounts => {
    let instance;

    before(async () => {
        instance = await getInstance(accounts);
    });

    it('should show pending Zorro rewards for single tranche', async () => {
        const contribution = web3.utils.toWei('1', 'ether');
        // Add tranche
        await instance.addTranche(
            0, //pid
            accounts[1],
            {
                contribution,
                timeMultiplier: 1,
                rewardDebt: 0,
                durationCommittedInWeeks: 0,
                enteredVaultAt: 0,
                exitedVaultAt: 0,
            }
            );
            
        const poolInfo = await instance.poolInfo.call(0);
        const elapsedBlocks = web3.utils.toBN(await web3.eth.getBlockNumber()).sub(poolInfo.lastRewardBlock);
        const zorPerBlock = await instance.ZORROPerBlock.call();
        const poolAllocPoints = web3.utils.toBN(1);
        const totAllocPoints = web3.utils.toBN(1);

        const accRewards = elapsedBlocks.mul(zorPerBlock).mul(poolAllocPoints).div(totAllocPoints);
        const totalContribs = (await instance.poolInfo.call(0)).totalTrancheContributions;
        const expPendingRewards = web3.utils.toBN(contribution).mul(accRewards).div(totalContribs);

        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[1], 
            0 // trancheId
        );

        assert.isTrue(pendingRewards.eq(expPendingRewards));
    });
});

contract('ZorroControllerAnalytics', async accounts => {
    let instance;

    before(async () => {
        instance = await getInstance(accounts);
    });

    it('should show zero pending Zorro rewards for exited tranche', async () => {
        const contribution = web3.utils.toWei('1', 'ether');
        // Add tranche
        await instance.addTranche(
            0, //pid
            accounts[1],
            {
                contribution,
                timeMultiplier: 1,
                rewardDebt: 0,
                durationCommittedInWeeks: 0,
                enteredVaultAt: 0,
                exitedVaultAt: 1650317689, // Unix timestamp
            }
        );

        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[1], 
            0 // trancheId
        );

        assert.equal(pendingRewards, 0);
    });
});

contract('ZorroControllerAnalytics', async accounts => {
    const contribution = web3.utils.toWei('1', 'ether');
    let instance;
    let contribs = web3.utils.toBN(0);

    before(async () => {
        // Get instance 
        instance = await getInstance(accounts);

        // Add tranches
        for (let i = 0; i < 2; i++) {
            await instance.addTranche(
                0, //pid
                accounts[2],
                {
                    contribution,
                    timeMultiplier: 1,
                    rewardDebt: 0,
                    durationCommittedInWeeks: 0,
                    enteredVaultAt: 0,
                    exitedVaultAt: 0,
                }
            );
            contribs = contribs.add(web3.utils.toBN(contribution));
        }
    });

    it('should show pending Zorro rewards for all tranches', async () => {
        // Prep
        const totalContribs = web3.utils.toBN((await instance.poolInfo.call(0)).totalTrancheContributions);
        const poolInfo = await instance.poolInfo.call(0);
        const elapsedBlocks = web3.utils.toBN(await web3.eth.getBlockNumber()).sub(poolInfo.lastRewardBlock);
        const zorPerBlock = await instance.ZORROPerBlock.call();
        console.log('elapsedBlocks: ', elapsedBlocks.toString());
        console.log('zorPerBlock: ', zorPerBlock.toString());
        const poolAllocPoints = web3.utils.toBN(1);
        const totAllocPoints = web3.utils.toBN(1);

        const accRewards = elapsedBlocks.mul(zorPerBlock).mul(poolAllocPoints).div(totAllocPoints);
        console.log('contribs: ', contribs.toString());
        console.log('accRewards: ', accRewards.toString());
        console.log('totalContribs: ', totalContribs.toString());
        const expPendingRewards = contribs.mul(accRewards).div(totalContribs);

        // Run
        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[2], 
            -1 // trancheId -1 means "all"
        );

        // Tests
        console.log('pendingRewards: ', pendingRewards.toString());
        console.log('expPendingRewards: ', expPendingRewards.toString());
        assert.isTrue(pendingRewards.eq(expPendingRewards));
    });

    it('should show the amt Want tokens staked for a single tranche', async () => {
        // Prep

        // Run
        const amtStaked = await instance.stakedWantTokens.call(
            0, // pid
            accounts[1], 
            0 // trancheId
        );

        // Tests
        assert.isTrue(amtStaked.eq(contribution));
    });

    it('should show the amt Want tokens staked for all tranches', async () => {
        // Prep
    
    
        // Run
        const amtStaked = await instance.stakedWantTokens.call(
            0, // pid
            accounts[1], 
            -1 // all tranches
        );
    
        // Tests
        assert.isTrue(amtStaked.eq(contribs));
    });
});