const MockZorroController = artifacts.require('MockZorroController');
const MockLPPool = artifacts.require('MockLPPool');
const MockInvestmentVault = artifacts.require('MockInvestmentVault');
const MockUSDC = artifacts.require('MockUSDC');
const MockZorroToken = artifacts.require("MockZorroToken");
const MockVaultZorro = artifacts.require("MockVaultZorro");
const PoolPublic = artifacts.require("PoolPublic");

const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
const depositedWantEventSig = web3.eth.abi.encodeEventSignature('DepositedWant(uint256)');
const withdrewWantEventSig = web3.eth.abi.encodeEventSignature('WithdrewWant(uint256)');
const exchangedUSDCForWantEventSig = web3.eth.abi.encodeEventSignature('ExchangedUSDCForWant(uint256,uint256)');
const exchangedWantForUSDCEventSig = web3.eth.abi.encodeEventSignature('ExchangedWantForUSDC(uint256,uint256)');

const setupObj = async (accounts) => {
    // Get contracts
    const instance = await MockZorroController.deployed();
    const lpPool = await MockLPPool.deployed();
    const vault = await MockInvestmentVault.deployed();
    const usdc = await MockUSDC.deployed();
    const ZORToken = await MockZorroToken.deployed();
    const ZORStakingVault = await MockVaultZorro.deployed();
    const publicPool = await PoolPublic.deployed();

    // Vault
    await vault.setZorroControllerAddress(instance.address);
    await vault.setWantAddress(lpPool.address);
    await vault.setBurnAddress(accounts[4]);
    await vault.setTokenUSDCAddress(usdc.address);

    // Config
    await instance.setXChainParams(
        0,
        0,
        instance.address
    );
    await instance.setKeyAddresses(
        ZORToken.address,
        usdc.address
    );
    await instance.setZorroContracts(
        publicPool.address,
        ZORStakingVault.address
    );
    await instance.setZorroXChainEndpoint(accounts[0]);

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
        lpPool.address, // _want address
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
        lpPool,
        vault,
        usdc,
        ZORStakingVault,
    };
};

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
    });

    it('sets time multiplier', async () => {
        // Normal
        await instance.setIsTimeMultiplierActive(true);
        assert.isTrue(await instance.isTimeMultiplierActive.call());
        await instance.setIsTimeMultiplierActive(false);
        assert.isFalse(await instance.isTimeMultiplierActive.call());
        // Only by owner
        try {
            await instance.setIsTimeMultiplierActive(true, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro LP Pool params', async () => {
        // Normal
        const lpPool = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const avaxToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroLPPoolParams(lpPool, avaxToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPool.call()), lpPool);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroLPPoolOtherToken.call()), avaxToken);
        // Only by owner
        try {
            await instance.setZorroLPPoolParams(lpPool, avaxToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets uni router', async () => {
        // Normal
        const uniRouter = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUniRouter(uniRouter);
        assert.equal(web3.utils.toChecksumAddress(await instance.uniRouterAddress.call()), uniRouter);
        // Only by owner
        try {
            await instance.setUniRouter(uniRouter, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets USDC to ZOR path', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const ZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUSDCToZORPath([USDC, ZOR]);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(0)), USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroPath.call(1)), ZOR);
        // Only by owner
        try {
            await instance.setUSDCToZORPath([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets USDC to ZOR LP pool token other path', async () => {
        // Normal
        const USDC = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const zorLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setUSDCToZorroLPPoolOtherTokenPath([USDC, zorLPPoolOtherToken]);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(0)), USDC);
        assert.equal(web3.utils.toChecksumAddress(await instance.USDCToZorroLPPoolOtherTokenPath.call(1)), zorLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setUSDCToZorroLPPoolOtherTokenPath([], { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets price feeds', async () => {
        // Normal
        const priceFeedZOR = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        const priceFeedLPPoolOtherToken = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setPriceFeeds(priceFeedZOR, priceFeedLPPoolOtherToken);
        assert.equal(web3.utils.toChecksumAddress(await instance.priceFeedZOR.call()), priceFeedZOR);
        assert.equal(web3.utils.toChecksumAddress(await instance.priceFeedLPPoolOtherToken.call()), priceFeedLPPoolOtherToken);
        // Only by owner
        try {
            await instance.setPriceFeeds(priceFeedZOR, priceFeedLPPoolOtherToken, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('sets Zorro X chain endpoint', async () => {
        // Normal
        const contract = web3.utils.toChecksumAddress(web3.utils.randomHex(20));
        await instance.setZorroXChainEndpoint(contract);
        assert.equal(web3.utils.toChecksumAddress(await instance.zorroXChainEndpoint.call()), contract);
        // Only by owner
        try {
            await instance.setZorroXChainEndpoint(contract, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });

    it('gets the correct time multiplier value', async () => {
        // Set time multiplier active
        await instance.setIsTimeMultiplierActive(true);
        // Prep 
        const durationCommittedWeeks = 5;

        // Assert 
        const multiplierFactor = await instance.getTimeMultiplier.call(durationCommittedWeeks);
        const expectedMultFactor = (1 + 0.2 * Math.sqrt(durationCommittedWeeks))*(1e12);
        assert.closeTo(multiplierFactor/1e12, expectedMultFactor/1e12, 0.01);
    });
});

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
    });

    it('gets the correct time multiplier value when time multiplier inactive', async () => {
        // Set time multiplier active
        await instance.setIsTimeMultiplierActive(false);

        // Prep 
        const durationCommittedWeeks = 5;

        // Assert 
        const multiplierFactor = await instance.getTimeMultiplier.call(durationCommittedWeeks);
        const expectedMultFactor = 1e12;
        assert.equal(multiplierFactor, expectedMultFactor);
    });
});

contract('ZorroControllerInvestment Main', async accounts => {
    let instance, lpPool, vault, usdc;

    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
        lpPool = obj.lpPool;
        vault = obj.vault;
        usdc = obj.usdc;
    });

    it('deposits Want token with local account', async () => {
        // Prep
        const pid = 0;
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.035', 'ether'));
        const weeksCommitted = 4; 

        // Mint want tokens to account
        await lpPool.mint(accounts[0], wantAmt);
        // Approve
        await lpPool.approve(instance.address, wantAmt);

        // Run
        const tx = await instance.deposit(pid, wantAmt, weeksCommitted);

        // Logs
        const { rawLogs } = tx.receipt;
        let depositedWant;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === depositedWantEventSig && web3.utils.toBN(topics[1]).eq(wantAmt)) {
                depositedWant = rl;
            }
        }

        // Test

        // Updates Pool reward
        const latestPoolInfo = await instance.poolInfo.call(pid);
        const latestBlock = web3.utils.toBN(await web3.eth.getBlockNumber());
        assert.isTrue(latestPoolInfo.lastRewardBlock.eq(latestBlock));

        // Performs Vault deposit
        assert.isNotNull(depositedWant);

        // Updates poolInfo
        const timeMultiplier = web3.utils.toBN((1 + 0.2 * Math.sqrt(weeksCommitted)) * 1e12);
        const contrib = wantAmt.mul(timeMultiplier).div(web3.utils.toBN(1e12));
        assert.isTrue(latestPoolInfo.totalTrancheContributions.eq(contrib));

        // Updates trancheInfo ledger
        const trancheInfo = await instance.trancheInfo.call(pid, accounts[0], 0);
        const blockts = (await web3.eth.getBlock('latest')).timestamp;
        assert.isTrue(trancheInfo.contribution.eq(contrib));
        assert.isTrue(trancheInfo.timeMultiplier.eq(timeMultiplier));
        assert.isTrue(trancheInfo.durationCommittedInWeeks.eq(web3.utils.toBN(weeksCommitted)));
        assert.isTrue(trancheInfo.enteredVaultAt.eq(web3.utils.toBN(blockts)));
        assert.isTrue(trancheInfo.exitedVaultAt.isZero());
    });

    it('deposits from USDC', async () => {
        // Prep
        const pid = 0;
        const valueUSDC = web3.utils.toBN(web3.utils.toWei('100', 'ether'));
        const weeksCommitted = 4;
        const maxMarketMovement = 990;

        // Mint and approve USDC
        await usdc.mint(accounts[0], valueUSDC);
        await usdc.approve(instance.address, valueUSDC);
    
        // Run 
        const tx = await instance.depositFullService(
            pid,
            valueUSDC,
            weeksCommitted,
            maxMarketMovement
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let exchangedUSDCForWant, depositedWant;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === exchangedUSDCForWantEventSig && web3.utils.toBN(topics[1]).eq(valueUSDC)) {
                exchangedUSDCForWant = rl;
            } else if (topics[0] === depositedWantEventSig && web3.utils.toBN(topics[1]).eq(valueUSDC)) {
                depositedWant = rl; // Assumes 1:1 exchange rate
            }
        }
    
        // Test
    
        // Assert exchanged USD for Want token
        assert.isNotNull(exchangedUSDCForWant);
        
        // Assert deposited Want token
        assert.isNotNull(depositedWant);
    });
});

contract('ZorroControllerInvestment::Withdraw', async accounts => {
    let instance, lpPool, vault;
    const depositWantAmt = web3.utils.toBN(web3.utils.toWei('10', 'ether'));
    
    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
        lpPool = obj.lpPool;
        vault = obj.vault;
        
    });
    
    it('withdraws Want token with local account, no time commitment', async () => {
        // Prep 
        // Deposit 
        const weeksCommitted = 0;
        await lpPool.mint(accounts[0], depositWantAmt);
        await lpPool.approve(instance.address, depositWantAmt);
        await instance.deposit(
            0, // pid
            depositWantAmt,
            weeksCommitted
        );
        const zpb = await instance.ZORROPerBlock.call();
        const pi = await instance.poolInfo.call(0);
        const tranche = await instance.trancheInfo.call(0, accounts[0], 0);

        // Run
        const tx = await instance.withdraw(
            0, // pid, 
            0, // trancheId, 
            false // harvestOnly
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let harvested, withdrewWant;

        const newAccRewards = pi.accZORRORewards.add(zpb);
        const rewardsDue = newAccRewards.sub(tranche.rewardDebt);
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && web3.utils.toBN(topics[2]).eq(web3.utils.toBN(accounts[0])) && web3.utils.toBN(rl.data).eq(rewardsDue)) {
                harvested = rl;
            } else if (topics[0] === withdrewWant && web3.utils.toBN(topics[1]).eq(depositWantAmt)) {
                withdrewWant = rl;
            }
        }

        // Test
        // Assert receives the full Want qty back
        assert.isNotNull(withdrewWant);
        const wantBal = await lpPool.balanceOf.call(accounts[0]);
        assert.isTrue(wantBal.eq(depositWantAmt));

        // Assert receives full rewards for elapsed blocks
        assert.isNotNull(harvested);
    });
});

contract('ZorroControllerInvestment::Withdraw', async accounts => {
    let instance, lpPool, vault, ZORStakingVault;
    const depositWantAmt = web3.utils.toBN(web3.utils.toWei('10', 'ether'));
    
    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
        lpPool = obj.lpPool;
        vault = obj.vault;
        ZORStakingVault = obj.ZORStakingVault;
    });

    it('withdraws Want token with local account, WITH penalty', async () => {
        // Prep 
        // Deposit 
        const weeksCommitted = 4;
        await lpPool.mint(accounts[0], depositWantAmt);
        await lpPool.approve(instance.address, depositWantAmt);
        await instance.deposit(
            0, // pid
            depositWantAmt,
            weeksCommitted
        );
        const zpb = await instance.ZORROPerBlock.call();
        const pi = await instance.poolInfo.call(0);
        const tranche = await instance.trancheInfo.call(0, accounts[0], 0);

        // Run
        const tx = await instance.withdraw(
            0, // pid, 
            0, // trancheId, 
            false // harvestOnly
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let harvested, slashed, withdrewWant;

        const newAccRewards = pi.accZORRORewards.add(zpb);
        const pendingRewards = newAccRewards.sub(tranche.rewardDebt);
        const block = (await web3.eth.getBlockNumber()) - 1;
        const blockTimestamp = (await web3.eth.getBlock(block)).timestamp;
        const timeRemainingSecs = tranche.enteredVaultAt.add(web3.utils.toBN(weeksCommitted * 7 * 60 * 60)).sub(web3.utils.toBN(blockTimestamp));
        const slashedRewards = pendingRewards.mul(timeRemainingSecs).div(web3.utils.toBN(weeksCommitted * 7 * 60 * 60));
        const rewardsDue = pendingRewards.sub(slashedRewards);
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && web3.utils.toBN(topics[2]).eq(web3.utils.toBN(accounts[0])) && web3.utils.toBN(rl.data).eq(rewardsDue)) {
                harvested = rl;
            } else if (topics[0] === withdrewWant && web3.utils.toBN(topics[1]).eq(depositWantAmt)) {
                withdrewWant = rl;
            } else if (topics[0] === transferredEventSig && web3.utils.toBN(topics[2]).eq(web3.utils.toBN(ZORStakingVault.address)) && web3.utils.toBN(rl.data).eq(slashedRewards)) {
                slashed = rl;
            }
        }

        // Test
        // Assert receives the full Want qty back
        assert.isNotNull(withdrewWant);
        const wantBal = await lpPool.balanceOf.call(accounts[0]);
        assert.isTrue(wantBal.eq(depositWantAmt));

        // Assert receives full rewards for elapsed blocks
        assert.isNotNull(harvested);
        // Assert slashes rewards and sends to ZOR stakers
        assert.isNotNull(slashed);
    });
});

contract('ZorroControllerInvestment::Withdraw', async accounts => {
    let instance, lpPool, vault, ZORStakingVault;
    const depositWantAmt = web3.utils.toBN(web3.utils.toWei('10', 'ether'));
    
    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
        lpPool = obj.lpPool;
        vault = obj.vault;
        ZORStakingVault = obj.ZORStakingVault;
    });

    it('withdraws Want token with local account, harvest only', async () => {
        // Prep 
        // Deposit 
        const weeksCommitted = 0;
        await lpPool.mint(accounts[0], depositWantAmt);
        await lpPool.approve(instance.address, depositWantAmt);
        await instance.deposit(
            0, // pid
            depositWantAmt,
            weeksCommitted
        );
        const zpb = await instance.ZORROPerBlock.call();
        const pi = await instance.poolInfo.call(0);
        const tranche = await instance.trancheInfo.call(0, accounts[0], 0);

        // Run
        const tx = await instance.withdraw(
            0, // pid, 
            0, // trancheId, 
            true // harvestOnly
        );

        // Logs
        const { rawLogs } = tx.receipt;
        let harvested, withdrewWant;

        const newAccRewards = pi.accZORRORewards.add(zpb);
        const rewardsDue = newAccRewards.sub(tranche.rewardDebt);
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && web3.utils.toBN(topics[2]).eq(web3.utils.toBN(accounts[0])) && web3.utils.toBN(rl.data).eq(rewardsDue)) {
                harvested = rl;
            } else if (topics[0] === withdrewWant && web3.utils.toBN(topics[1]).eq(depositWantAmt)) {
                withdrewWant = rl;
            }
        }

        // Test
        // Assert receives the full Want qty back
        assert.isUndefined(withdrewWant);
        const wantBal = await lpPool.balanceOf.call(accounts[0]);
        console.log('wantBal: ', wantBal.toString());
        assert.isTrue(wantBal.isZero());

        // Assert receives full rewards for elapsed blocks
        assert.isNotNull(harvested);
    });

    xit('withdraws to USDC', async () => {

    });

    xit('withdraws all tranches owned by a user in a pool', async () => {
    
    });

    xit('transfers investment', async () => {
    
    });
});

contract('ZorroControllerInvestment::Withdraw Cross Chain', async accounts => {
    let instance, lpPool, vault;

    before(async () => {
        const obj = await setupObj(accounts);
        instance = obj.instance;
        lpPool = obj.lpPool;
        vault = obj.vault;
    });

    xit('withdraws Want token with foreign account', async () => {

    });

    it('does not withdraw when both addresses given', async () => {
        // Prep 

        // Run
        try {
            await instance.withdrawalFullServiceFromXChain(
                accounts[0],
                web3.utils.hexToBytes(web3.utils.asciiToHex("xyz123_abc")),
                0,
                0,
                false,
                990
            );
        } catch (err) {
            // Test
            assert.include(err.message, 'Only one account type allowed');
        }
    });
});