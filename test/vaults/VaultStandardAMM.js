const MockVaultStandardAMM = artifacts.require('MockVaultStandardAMM');
const MockVaultFactoryStandardAMM = artifacts.require('MockVaultFactoryStandardAMM');
const MockAMMWantToken = artifacts.require('MockAMMWantToken');
const MockAMMFarm = artifacts.require('MockAMMFarm');
const zeroAddress = '0x0000000000000000000000000000000000000000';


contract('VaultFactoryStandardAMM', async accounts => {
    let factory;
    let instance;
    const initVal = {
        pid: 0,
        isHomeChain: true,
        keyAddresses: {
            govAddress: accounts[0],
            zorroControllerAddress: zeroAddress,
            ZORROAddress: zeroAddress,
            zorroStakingVault: zeroAddress,
            wantAddress: zeroAddress,
            token0Address: zeroAddress,
            token1Address: zeroAddress,
            earnedAddress: zeroAddress,
            farmContractAddress: zeroAddress,
            rewardsAddress: zeroAddress,
            poolAddress: zeroAddress,
            uniRouterAddress: zeroAddress,
            zorroLPPool: zeroAddress,
            zorroLPPoolOtherToken: zeroAddress,
            tokenUSDCAddress: zeroAddress,
        },
        earnedToZORROPath: [],
        earnedToToken0Path: [],
        earnedToToken1Path: [],
        USDCToToken0Path: [],
        USDCToToken1Path: [],
        earnedToZORLPPoolOtherTokenPath: [],
        earnedToUSDCPath: [],
        fees: {
            controllerFee: 0,
            buyBackRate: 0,
            revShareRate: 0,
            entranceFeeFactor: 0,
            withdrawFeeFactor: 0,
        },
        priceFeeds: {
            token0PriceFeed: zeroAddress,
            token1PriceFeed: zeroAddress,
            earnTokenPriceFeed: zeroAddress,
            ZORPriceFeed: zeroAddress,
            lpPoolOtherTokenPriceFeed: zeroAddress,
        },
    };

    before(async () => {
        factory = await MockVaultFactoryStandardAMM.deployed();
        instance = await MockVaultStandardAMM.deployed();
    });

    it('has a master vault', async () => {
        assert.equal(await factory.masterVault.call(), instance.address);
    });

    it('creates a vault', async () => {
        // Create vault
        await factory.createVault(accounts[0], initVal);

        // Check creation
        assert.equal(await factory.numVaults.call(), 1);
        assert.isNotNull(await factory.deployedVaults.call(0));

        // Only owner
        try {
            await factory.createVault(accounts[0], initVal, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, 'caller is not the owner');
        }
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
        // Set controller
        await instance.setZorroControllerAddress(accounts[0]);
        // Set other tokens/contracts
        wantToken = await MockAMMWantToken.deployed();
        farmContract = await MockAMMFarm.deployed();
        await farmContract.setWantAddress(wantToken.address);
        await farmContract.setBurnAddress(accounts[4]);
        await instance.setWantAddress(wantToken.address);
        await instance.setFarmContractAddress(farmContract.address);
    });

    it('deposits Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));

        /* Deposit (0) */
        try {
            await instance.depositWantToken(account, 0);
        } catch (err) {
            assert.include(err.message, 'Want dep < 0');
        }

        // Mint some tokens
        await wantToken.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await wantToken.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());

        /* First deposit */
        // Deposit
        const tx = await instance.depositWantToken(account, wantAmt);

        // Logs
        const { rawLogs } = tx.receipt;
        const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
        const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(uint256,uint256)');
        let transferred;
        let farmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig && !transferred) {
                transferred = rl;
            } else if (topics[0] === depositedEventSig) {
                farmed = rl;
            }
        }

        // Assert: transfers Want token
        assert.equal(web3.utils.toChecksumAddress(web3.utils.toHex(web3.utils.toBN(transferred.topics[1]))), accounts[0]);
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));

        // Assert: increments shares (total shares and user shares)
        assert.isTrue((await instance.sharesTotal.call()).eq(wantAmt));
        assert.isTrue((await instance.userShares.call(account)).eq(wantAmt));

        // Assert: calls farm()
        assert.isNotNull(farmed);

        /* Next deposit */
        // Set fees
        await instance.setFeeSettings(
            9990, // 0.1% deposit fee
            10000,
            0,
            0
        );
        // Deposit
        await instance.depositWantToken(account, wantAmt);

        // Assert: returns correct shares added (based on current shares etc.)
        const sharesTotal = wantAmt; // Total shares before second deposit
        const wantLockedTotal = wantAmt; // Total want locked before second deposit
        const sharesAdded = wantAmt.mul(sharesTotal).mul(web3.utils.toBN(9990)).div(wantLockedTotal.mul(web3.utils.toBN(10000)));
        const newTotalShares = web3.utils.toBN(sharesAdded).add(wantAmt);
        assert.isTrue((await instance.sharesTotal.call()).eq(newTotalShares));
        assert.isTrue((await instance.userShares.call(account)).eq(newTotalShares));

        /* Only Zorro controller */
        try {
            await instance.depositWantToken(zeroAddress, 0, { from: accounts[1] });
        } catch (err) {
            assert.include(err.message, '!zorroController');
        }
    });

    it('withdraws Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.547', 'ether'));
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentUserShares = await instance.userShares.call(account);
        const currentWantLockedTotal = await instance.wantLockedTotal.call();

        /* Withdraw 0 */
        try {
           await instance.withdrawWantToken(account, 0); 
        } catch (err) {
            assert.include(err.message, 'want amt <= 0');
        }
        
        /* Withdraw > 0 */
        
        // Withdraw
        const tx = await instance.withdrawWantToken(account, wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
        const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
        let transferred;
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            } else if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: Correct sharesTotal and userShares
        const sharesRemoved = wantAmt.mul(currentSharesTotal).div(currentWantLockedTotal);
        const expectedSharesTotal = currentSharesTotal.sub(sharesRemoved);
        const expectedUserShares = currentUserShares.sub(sharesRemoved);
        assert.isTrue((await instance.sharesTotal.call()).eq(expectedSharesTotal));
        assert.isTrue((await instance.userShares.call(account)).eq(expectedUserShares));

        // Assert: calls unfarm()
        assert.isNotNull(unfarmed);

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(wantAmt));
    });

    it('withdraws safely when excess Want token specified', async () => {
        // Prep
        const currentSharesTotal = await instance.sharesTotal.call();
        const currentUserShares = await instance.userShares.call(account);
        const currentWantLockedTotal = await instance.wantLockedTotal.call();
        const wantAmt = currentWantLockedTotal.add(web3.utils.toBN(1e12)); // Set to exceed the tokens locked, intentionally

        /* Withdraw > wantToken */

        // Withdraw
        const tx = await instance.withdrawWantToken(account, wantAmt); 

        // Get logs
        const { rawLogs } = tx.receipt;
        const transferredEventSig = web3.eth.abi.encodeEventSignature('Transfer(address,address,uint256)');
        const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
        let transferred;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === transferredEventSig) {
                transferred = rl;
            }
        }

        // Assert: Correct sharesTotal and userShares
        assert.isTrue((await instance.sharesTotal.call()).isZero());
        assert.isTrue((await instance.userShares.call(account)).isZero());

        // Assert: Xfers back to controller and for wantAmt
        assert.equal(web3.utils.toHex(web3.utils.toBN(transferred.data)), web3.utils.toHex(currentWantLockedTotal));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
        // Set controller
        await instance.setZorroControllerAddress(accounts[0]);
        // Set other tokens/contracts
        wantToken = await MockAMMWantToken.deployed();
        farmContract = await MockAMMFarm.deployed();
        await instance.setWantAddress(wantToken.address);
        await instance.setFarmContractAddress(farmContract.address);
    });

    xit('exchanges USD for Want token', async () => {
        // Check auth
    });

    xit('exchanges Want token for USD', async () => {
        // Check auth
    });

    xit('auto compounds and earns', async () => {
        // Check auth
    });

    xit('buys back Earn token, adds liquidity, and burns LP', async () => {
        // Check auth
    });

    xit('shares revenue with ZOR stakers', async () => {
        // Check auth
    });

    xit('swaps Earn token to USD', async () => {
        // Check auth
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
        // Set controller
        await instance.setZorroControllerAddress(accounts[0]);
        // Set other tokens/contracts
        wantToken = await MockAMMWantToken.deployed();
        farmContract = await MockAMMFarm.deployed();
        await farmContract.setWantAddress(wantToken.address);
        await farmContract.setBurnAddress(accounts[4]);
        await instance.setWantAddress(wantToken.address);
        await instance.setFarmContractAddress(farmContract.address);
    });

    it('farms Want token', async () => {
        // Mint tokens
        const wantAmt = web3.utils.toBN(web3.utils.toWei('0.628', 'ether'));
        await wantToken.mint(instance.address, wantAmt);
        // Farm
        const tx = await instance.farm();
        const { rawLogs } = tx.receipt;

        const depositedEventSig = web3.eth.abi.encodeEventSignature('Deposited(uint256,uint256)');
        const approvalEventSig = web3.eth.abi.encodeEventSignature('Approval(address,address,uint256)');
        let depositedInFarm;
        let approvedSpending;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === depositedEventSig) {
                depositedInFarm = rl;
            } else if (topics[0] === approvalEventSig && !approvedSpending) {
                approvedSpending = rl;
            }
        }

        // Assert: Increments Want locked total
        assert.isTrue((await instance.wantLockedTotal.call()).eq(wantAmt));

        // Assert: Allows farm contract to spend
        assert.equal(web3.utils.toHex(web3.utils.toBN(approvedSpending.data)), web3.utils.toHex(wantAmt));

        // Assert: farms token (wantLockedTotal incremented, farm's deposit() func called)
        assert.isTrue(web3.utils.toBN(depositedInFarm.topics[2]).eq(wantAmt));
    });
});

contract('VaultStandardAMM', async accounts => {
    let instance;
    const account = web3.utils.toChecksumAddress(web3.utils.randomHex(20));

    before(async () => {
        instance = await MockVaultStandardAMM.deployed();
        // Set controller
        await instance.setZorroControllerAddress(accounts[0]);
        // Set other tokens/contracts
        wantToken = await MockAMMWantToken.deployed();
        farmContract = await MockAMMFarm.deployed();
        await farmContract.setWantAddress(wantToken.address);
        await farmContract.setBurnAddress(accounts[4]);
        await instance.setWantAddress(wantToken.address);
        await instance.setFarmContractAddress(farmContract.address);
    });

    it('unfarms Want token', async () => {
        // Prep
        const wantAmt = web3.utils.toBN(1e17)
        
        // Mint some tokens
        await wantToken.mint(accounts[0], wantAmt.mul(web3.utils.toBN('2')).toString());
        // Approval
        await wantToken.approve(instance.address, wantAmt.mul(web3.utils.toBN('2')).toString());
        // Simulate deposit
        await instance.depositWantToken(account, wantAmt);
        const wantLockedTotal = await instance.wantLockedTotal.call();

        // Unfarm
        const tx = await instance.unfarm(wantAmt);

        // Get logs
        const { rawLogs } = tx.receipt;
        const withdrewEventSig = web3.eth.abi.encodeEventSignature('Withdrew(uint256,uint256)');
        let unfarmed;
        for (let rl of rawLogs) {
            const { topics } = rl;
            if (topics[0] === withdrewEventSig) {
                unfarmed = rl;
            }
        }

        // Assert: called unfarm() func
        assert.isTrue(web3.utils.toBN(unfarmed.topics[1]).eq(await instance.pid.call()));
        assert.isTrue(web3.utils.toBN(unfarmed.topics[2]).eq(wantAmt));

        // Assert wantLockedTotal updated
        assert.isTrue((await instance.wantLockedTotal.call()).isZero());
    });
});