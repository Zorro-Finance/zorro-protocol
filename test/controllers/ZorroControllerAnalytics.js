const MockZorroController = artifacts.require('MockZorroController');
const MockVaultZorro = artifacts.require("MockVaultZorro");
const MockZorroToken = artifacts.require("MockZorroToken");

const setupObj = async (accounts) => {
    // Get instance 
    const instance = await MockZorroController.deployed();
    const vault = await MockVaultZorro.deployed();
    const ZORToken = await MockZorroToken.deployed();

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
        ZORToken.address, // _want address
        true, // withUpdate
        vault.address // _vault address
    );

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

    return {
        instance,
        vault,
        ZORToken
    };
};


contract('ZorroControllerAnalytics::Pending Rewards', async accounts => {
    let instance;

    before(async () => {
        instance = (await setupObj(accounts)).instance;
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
        // Prep
        const contribution = web3.utils.toWei('1', 'ether');
        let contribs = web3.utils.toBN(0);
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

        // Vars
        const totalContribs = web3.utils.toBN((await instance.poolInfo.call(0)).totalTrancheContributions);
        const poolInfo = await instance.poolInfo.call(0);
        const elapsedBlocks = web3.utils.toBN(await web3.eth.getBlockNumber()).sub(poolInfo.lastRewardBlock);
        const zorPerBlock = await instance.ZORROPerBlock.call();

        const poolAllocPoints = web3.utils.toBN(1);
        const totAllocPoints = web3.utils.toBN(1);

        const accRewards = elapsedBlocks.mul(zorPerBlock).mul(poolAllocPoints).div(totAllocPoints);
        const expPendingRewards = contribs.mul(accRewards).div(totalContribs);

        // Run
        const pendingRewards = await instance.pendingZORRORewards.call(
            0, // pid
            accounts[2],
            -1 // trancheId -1 means "all"
        );

        // Tests
        assert.closeTo(pendingRewards.div(web3.utils.toBN(1e18)).toNumber(), expPendingRewards.div(web3.utils.toBN(1e18)).toNumber(), 1);
    });
});

contract('ZorroControllerAnalytics::Staked Want tokens', async accounts => {
    let instance, vault, ZORToken;

    before(async () => {
        // Setup
        const obj = await setupObj(accounts);
        // Get instance 
        instance = obj.instance;
        vault = obj.vault;
        ZORToken = obj.ZORToken;
        // Set ZC 
        await vault.setZorroControllerAddress(accounts[0]);
        // Set addresses
        await vault.setWantAddress(ZORToken.address);
        await vault.setToken0Address(ZORToken.address);
        // Set fees
        await vault.setFeeSettings(
            10e3, // Entrance FF
            10e3, // Withdraw FF
            0, // Controller Fee
            0, // BB rate
            0 // Revshare rate
        );
    });

    it('should show the amt Want tokens staked for a single tranche', async () => {
        // Prep
        const amtDeposit = web3.utils.toWei('1', 'ether');
        // Mint token, approve
        await ZORToken.mint(accounts[0], amtDeposit);
        await ZORToken.approve(vault.address, amtDeposit);
        // Deposit Want token
        await vault.depositWantToken(accounts[0], amtDeposit);
        // Add tranche
        await instance.addTranche(
            0, //pid
            accounts[0],
            {
                contribution: amtDeposit,
                timeMultiplier: 1,
                rewardDebt: 0,
                durationCommittedInWeeks: 0,
                enteredVaultAt: 0,
                exitedVaultAt: 0,
            }
        );

        // Run
        const amtStaked = await instance.stakedWantTokens.call(
            0, // pid
            accounts[0],
            0 // trancheId
        );

        // Tests
        assert.isTrue(amtStaked.eq(web3.utils.toBN(amtDeposit)));
    });

    it('should show the amt Want tokens staked for all tranches', async () => {
        // Prep
        let contribs = web3.utils.toBN(0);

        for (let i = 0; i < 3; i++) {
            // Prep
            const amtDeposit = web3.utils.toWei('1', 'ether');
            // Mint token, approve
            await ZORToken.mint(accounts[1], amtDeposit, { from: accounts[1] });
            await ZORToken.approve(vault.address, amtDeposit, { from: accounts[1] });
            // Set ZC 
            await vault.setZorroControllerAddress(accounts[1]);
            // Deposit Want token
            await vault.depositWantToken(accounts[1], amtDeposit, { from: accounts[1] });
            // Add tranche
            await instance.addTranche(
                0, //pid
                accounts[1],
                {
                    contribution: amtDeposit,
                    timeMultiplier: 1,
                    rewardDebt: 0,
                    durationCommittedInWeeks: 0,
                    enteredVaultAt: 0,
                    exitedVaultAt: 0,
                }
            );
            contribs = contribs.add(web3.utils.toBN(amtDeposit));
        }

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