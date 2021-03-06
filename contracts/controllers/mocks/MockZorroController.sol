// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroController.sol";

import "../../vaults/_VaultBase.sol";

import "../../tokens/mocks/MockToken.sol";

contract MockZorroController is ZorroController {
    event UpdatedPool(uint256 indexed _amount);
    event HandledRewards(uint256 indexed _rewardsDue);

    function addTranche(
        uint256 _pid,
        address _account,
        TrancheInfo memory _trancheInfo
    ) public {
        trancheInfo[_pid][_account].push(_trancheInfo);
        poolInfo[_pid].totalTrancheContributions =
            poolInfo[_pid].totalTrancheContributions +
            _trancheInfo.contribution;
    }

    function setLastRewardBlock(uint256 _pid, uint256 _block) public {
        poolInfo[_pid].lastRewardBlock = _block;
    }

    function updatePoolMod(uint256 _pid) public {
        uint256 _res = updatePool(_pid);

        emit UpdatedPool(_res);
    }

    function withdrawMod(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _trancheId,
        bool _harvestOnly,
        bool _xChainRepatriation
    ) public returns (WithdrawalResult memory _res) {
        _res = _withdraw(
            _pid,
            _localAccount,
            _foreignAccount,
            _trancheId,
            _harvestOnly,
            _xChainRepatriation
        );
        emit HandledRewards(_res.rewardsDueXChain);
    }

    function _fetchFundsFromPublicPool(uint256 _amount, address _destination)
        internal
        override
    {
        // Do nothing. Dummy func.
    }

    function recordMintedRewards(uint256 _mintedRewards)
        public
        nonHomeChainOnly
    {
        _recordMintedRewards(_mintedRewards);
    }

    function recordSlashedRewards(uint256 _slashedRewards)
        public
        nonHomeChainOnly
    {
        _recordSlashedRewards(_slashedRewards);
    }
}

contract MockInvestmentVault is VaultBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    event DepositedWant(uint256 indexed _wantAmt);
    event ExchangedUSDCForWant(
        uint256 indexed _amountUSDC,
        uint256 indexed _amountWant
    );
    event WithdrewWant(uint256 indexed _wantAmt);
    event ExchangedWantForUSDC(
        uint256 indexed _amountWant,
        uint256 indexed _amountUSDC
    );

    function depositWantToken(address _account, uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            burnAddress,
            _wantAmt
        );

        sharesTotal = sharesTotal.add(_wantAmt);

        wantLockedTotal = wantLockedTotal.add(_wantAmt);

        emit DepositedWant(_wantAmt);

        return _wantAmt;
    }

    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        IERC20Upgradeable(tokenUSDCAddress).safeTransfer(
            burnAddress,
            _amountUSDC
        );
        // Assume 1:1 exch rate
        MockERC20Upgradeable(wantAddress).mint(msg.sender, _amountUSDC);

        emit ExchangedUSDCForWant(_amountUSDC, _amountUSDC);

        return _amountUSDC;
    }

    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        sharesTotal = sharesTotal.sub(_wantAmt);

        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        MockERC20Upgradeable(wantAddress).mint(msg.sender, _wantAmt);

        emit WithdrewWant(_wantAmt);
    }

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256)
    {
        // Assume 1:1 exch rate
        MockERC20Upgradeable(tokenUSDCAddress).mint(msg.sender, _amount);

        emit ExchangedWantForUSDC(_amount, _amount);

        return _amount;
    }

    function earn(uint256 _maxMarketMovementAllowed) public override {}

    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {}

    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {}

    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {}

    function farm() external {}
}

contract MockInvestmentVault1 is MockInvestmentVault {}
