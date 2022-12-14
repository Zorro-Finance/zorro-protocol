// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroController.sol";

import "../../vaults/_VaultBase.sol";

import "../../tokens/mocks/MockToken.sol";

import "../../vaults/actions/_VaultActions.sol";

contract MockZorroController is ZorroController {
    event UpdatedVault(uint256 indexed _amount);
    event HandledRewards(uint256 indexed _rewardsDue);

    function addTranche(
        uint256 _vid,
        address _account,
        TrancheInfo memory _trancheInfo
    ) public {
        trancheInfo[_vid][_account].push(_trancheInfo);
        vaultInfo[_vid].totalTrancheContributions =
            vaultInfo[_vid].totalTrancheContributions +
            _trancheInfo.contribution;
    }

    function setLastRewardBlock(uint256 _vid, uint256 _block) public {
        vaultInfo[_vid].lastRewardBlock = _block;
    }

    function updateVaultMod(uint256 _vid) public {
        uint256 _res = updateVault(_vid);

        emit UpdatedVault(_res);
    }

    function withdrawMod(
        uint256 _vid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _trancheId,
        bool _harvestOnly,
        bool _xChainRepatriation
    ) public returns (WithdrawalResult memory _res) {
        _res = _withdraw(
            _vid,
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
    event ExchangedUSDForWant(
        uint256 indexed _amountUSD,
        uint256 indexed _amountWant
    );
    event WithdrewWant(uint256 indexed _wantAmt);
    event ExchangedWantForUSD(
        uint256 indexed _amountWant,
        uint256 indexed _amountUSD
    );

    function depositWantToken(uint256 _wantAmt)
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

        emit DepositedWant(_wantAmt);

        return _wantAmt;
    }

    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        require(_maxMarketMovementAllowed > 0, "slippage cannot be infinite");

        IERC20Upgradeable(defaultStablecoin).safeTransfer(
            burnAddress,
            _amountUSD
        );
        // Assume 1:1 exch rate
        MockERC20Upgradeable(wantAddress).mint(msg.sender, _amountUSD);

        emit ExchangedUSDForWant(_amountUSD, _amountUSD);

        return _amountUSD;
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
        // Requirements
        require(_maxMarketMovementAllowed > 0, "cannot have infinite slippage");
        // Assume 1:1 exch rate
        MockERC20Upgradeable(defaultStablecoin).mint(msg.sender, _amount);

        emit ExchangedWantForUSD(_amount, _amount);

        return _amount;
    }

    function earn(uint256 _maxMarketMovementAllowed) public override {}

    function farm() external {}

    function _farm() internal override {}

    function _unfarm(uint256 _amount) internal override {}
}

contract MockInvestmentVault1 is MockInvestmentVault {}
