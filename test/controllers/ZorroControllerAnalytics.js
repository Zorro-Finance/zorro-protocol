const MockZorroController = artifacts.require('MockZorroController');


contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        // Get instance 
        instance = await MockZorroController.deployed();
        const accounts = await web3.eth.getAccounts();
        console.log('acct: ', accounts[0]);

        // Determine owner
        const owner = await instance.owner.call();
        console.log('owner: ', owner);

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

        console.log('added pool');

        // Set Zorro Oracle (to allow setting below)
        await instance.setZorroControllerOracle(accounts[0]);

        console.log('set Zor controller');

        // Set ZORROPerBlock
        await instance.setZorroPerBlock(
            1,
            10e9,
            5000,
            1e6,
            800000
        );

        console.log('setZor per block');

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

        const elapsedBlocks = await web3.eth.getBlockNumber(); // Assumes last reward block = 0
        const zorPerBlock = await instance.ZORROPerBlock.call();
        const poolAllocPoints = 1;
        const totAllocPoints = 1;

        const accRewards = elapsedBlocks * zorPerBlock * poolAllocPoints / totAllocPoints;
        const totalContribs = (await instance.poolInfo.call(0)).totalTrancheContributions;
        const expPendingRewards = contribution * accRewards / totalContribs;

        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[1], 
            0 // trancheId
        );

        assert.equal(pendingRewards, expPendingRewards);
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
            1 // trancheId
        );

        assert.equal(pendingRewards, 0);
    });

    it('should show pending Zorro rewards for all tranches', async () => {
        // Add tranche
        const contribution = web3.utils.toWei('1', 'ether');
        let contribs = 0;
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
            contribs += contribution;
        }
        const totalContribs = (await instance.poolInfo.call(0)).totalTrancheContributions;

        const elapsedBlocks = await web3.eth.getBlockNumber(); // Assumes last reward block = 0
        const zorPerBlock = await instance.ZORROPerBlock.call();
        const poolAllocPoints = 1;
        const totAllocPoints = 1;

        const accRewards = elapsedBlocks * zorPerBlock * poolAllocPoints / totAllocPoints;
        const expPendingRewards = contribs * accRewards / totalContribs;

        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[2], 
            -1 // trancheId -1 means "all"
        );

        assert.equal(pendingRewards, expPendingRewards);
    });

    xit('should show pending Zorro rewards when time multiplier set', async () => {

    });

    xit('should show the amt Want tokens staked', async () => {

    });
})