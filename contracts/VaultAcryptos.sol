// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";

import "./interfaces/IAMMFarm.sol";

import "./interfaces/IAcryptosFarm.sol";

import "./interfaces/IAcryptosVault.sol";

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";

import "./VaultBase.sol";

import "./interfaces/IBalancerVault.sol";

/// @title Vault contract for Acryptos single token strategies (e.g. for lending)
contract VaultAcryptosSingle is VaultBase {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* Constructor */

  constructor(
    address[] memory _addresses,
    uint256 _pid,
    bool _isCOREStaking,
    bool _isSameAssetDeposit,
    bool _isZorroComp,
    address[] memory _earnedToZORROPath,
    address[] memory _earnedToToken0Path,
    address[] memory _earnedToToken1Path,
    address[] memory _token0ToEarnedPath,
    address[] memory _token1ToEarnedPath,
    uint256 _controllerFee,
    uint256 _buyBackRate,
    uint256 _entranceFeeFactor,
    uint256 _withdrawFeeFactor
  ) {
        wbnbAddress = _addresses[0];
        govAddress = _addresses[1];
        zorroControllerAddress = _addresses[2];
        ZORROAddress = _addresses[3];

        wantAddress = _addresses[4];
        token0Address = _addresses[5];
        token1Address = _addresses[6];
        earnedAddress = _addresses[7];

        farmContractAddress = _addresses[8];
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSameAssetDeposit = _isSameAssetDeposit;
        isZorroComp = _isZorroComp;

        uniRouterAddress = _addresses[9];
        earnedToZORROPath = _earnedToZORROPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        controllerFee = _controllerFee;
        rewardsAddress = _addresses[10];
        buyBackRate = _buyBackRate;
        burnAddress = _addresses[11];
        entranceFeeFactor = _entranceFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;

        transferOwnership(zorroControllerAddress);
    }

  /* State */

  address public balancerVaultAddress = 0xa82f327BBbF0667356D2935C6532d164b06cEced; // Address of Balancer/ACSI.finance Vault for swaps etc.
  bytes32 public balancerPoolEarnedToToken0 = 0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001; // The Acryptos ACSI.finance pool ID for swapping Earned token to token0. 
  uint256 balancerPoolEarnedWeightBasisPoints = 4000; 
  uint256 balancerPoolToken0WeightBasisPoints = 3000; 

  /* Config */

    function setBalancerVaultAddress(address _balancerVaultAddress) public onlyOwner {
        balancerVaultAddress = _balancerVaultAddress;
    }
    function setBalancerPoolEarnedToToken0(bytes32 _balancerPoolEarnedToToken0) public onlyOwner {
        balancerPoolEarnedToToken0 = _balancerPoolEarnedToToken0;
    }
    function setBalancerPoolEarnedWeightBasisPoints(uint256 _balancerPoolEarnedWeightBasisPoints) public onlyOwner {
        balancerPoolEarnedWeightBasisPoints = _balancerPoolEarnedWeightBasisPoints;
    }
    function setBalancerPoolToken0WeightBasisPoints(uint256 _balancerPoolToken0WeightBasisPoints) public onlyOwner {
        balancerPoolToken0WeightBasisPoints = _balancerPoolToken0WeightBasisPoints;
    }

  /* Investment Actions */

  /// @notice Receives new deposits from user
  /// @param _wantAmt amount of Want token to deposit/stake
  /// @return Number of shares added
  function deposit(uint256 _wantAmt) public virtual onlyOwner nonReentrant whenNotPaused returns (uint256) {
      // Transfer Want token from current user to this contract
      IERC20(wantAddress).safeTransferFrom(
          address(msg.sender),
          address(this),
          _wantAmt
      );
      // Set sharesAdded to the Want token amount specified
      uint256 sharesAdded = _wantAmt;
      // If the total number of shares and want tokens locked both exceed 0, the shares added is the proportion of Want tokens locked, 
      // discounted by the entrance fee 
      if (wantLockedTotal > 0 && sharesTotal > 0) {
          sharesAdded = _wantAmt
              .mul(sharesTotal)
              .mul(entranceFeeFactor)
              .div(wantLockedTotal)
              .div(entranceFeeFactorMax);
      }
      // Increment the shares
      sharesTotal = sharesTotal.add(sharesAdded);

      if (isZorroComp) {
          // If this contract is meant for Autocompounding, start to farm the staked token
          _farm();
      } else {
          // Otherwise, simply increment the quantity of total Want tokens locked
          wantLockedTotal = wantLockedTotal.add(_wantAmt);
      }

      return sharesAdded;
  }

  /// @notice Public function for farming Want token. 
  function farm() public virtual nonReentrant {
      _farm();
  }

  /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
  function _farm() internal virtual {
      // Farming should only occur if this contract is set for autocompounding
      require(isZorroComp, "!isZorroComp");

      // Get the Want token stored on this contract
      uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
      // Increment the total Want tokens locked into this contract
      wantLockedTotal = wantLockedTotal.add(wantAmt);
      // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
      IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

      // Deposit the Want tokens in the Farm contract 
      IAcryptosFarm(farmContractAddress).deposit(wantAddress, wantAmt);
  }

  /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
  /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
  function _unfarm(uint256 _wantAmt) internal virtual {
    // Withdraw the Want tokens from the Farm contract
    IAcryptosFarm(farmContractAddress).withdraw(wantAddress, _wantAmt);
  }

  /// @notice Withdraw Want tokens from the Farm contract
  /// @param _wantAmt the amount of Want tokens to withdraw
  /// @return the number of shares removed
  function withdraw(uint256 _wantAmt) public virtual onlyOwner nonReentrant returns (uint256) {
      // Want amount must be greater than 0
      require(_wantAmt > 0, "_wantAmt <= 0");

      // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
      uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
      // Safety: cap the shares to the total number of shares
      if (sharesRemoved > sharesTotal) {
          sharesRemoved = sharesTotal;
      }
      // Decrement the total shares by the sharesRemoved
      sharesTotal = sharesTotal.sub(sharesRemoved);

      // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
      if (withdrawFeeFactor < withdrawFeeFactorMax) {
          _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
              withdrawFeeFactorMax
          );
      }

      // If this contract is designated for auto compounding, unfarm the Want tokens
      if (isZorroComp) {
          _unfarm(_wantAmt);
      }

      // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
      uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
      if (_wantAmt > wantAmt) {
          _wantAmt = wantAmt;
      }
      // Safety: cap _wantAmt at the total quantity of Want tokens locked
      if (wantLockedTotal < _wantAmt) {
          _wantAmt = wantLockedTotal;
      }

      // Decrement the total Want locked tokens by the _wantAmt
      wantLockedTotal = wantLockedTotal.sub(_wantAmt);

      // Finally, transfer the want amount from this contract, back to the ZorroController contract
      IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

      return sharesRemoved;
  }

  /// @notice The main compounding (earn) function. Reinvests profits since the last earn event. 
  function earn() public virtual nonReentrant whenNotPaused {
      // Only to be run if this contract is configured for auto-comnpounding
      require(isZorroComp, "!isZorroComp");
      // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
      if (onlyGov) {
          require(msg.sender == govAddress, "!gov");
      }

      // Harvest farm tokens
      _unfarm(0);

      // If the earned address is the WBNB token, wrap all BNB owned by this contract
      if (earnedAddress == wbnbAddress) {
          _wrapBNB();
      }

      // Get the balance of the Earned token on this contract (ACS, etc.)
      uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

      // Reassign value of earned amount after distributing fees
      earnedAmt = distributeFees(earnedAmt);
      // Reassign value of earned amount after buying back a certain amount of Zorro
      earnedAmt = buyBack(earnedAmt);

      // If staking a single token (CAKE, BANANA), farm that token and exit
      if (isCOREStaking || isSameAssetDeposit) {
          // Update the last earn block
          lastEarnBlock = block.number;
          _farm();
          return;
      }

      // Approve the Balancer Vault contract for swaps
      IERC20(earnedAddress).safeApprove(balancerVaultAddress, 0);
      // Allow the Balancer Vault contract to spen up to earnedAmt
      IERC20(earnedAddress).safeIncreaseAllowance(balancerVaultAddress, earnedAmt);

      // Swap Earned token to token0 if token0 is not the Earned token
      if (earnedAddress != token0Address) {
          // Determine the limit based on the exchange rate
          uint256 limit = getExchangeRateEarnedToToken0().mul(slippageFactor).div(1000);
          // Swap Earned token to token0
          IBalancerVault(balancerVaultAddress).swap(
            SingleSwap({
              poolId: balancerPoolEarnedToToken0,
              kind: SwapKind.GIVEN_IN,
              assetIn: IAsset(earnedAddress),
              assetOut: IAsset(token0Address),
              amount: earnedAmt,
              userData: ""
            }),
            FundManagement({
              sender: address(this),
              fromInternalBalance: false,
              recipient: payable(address(this)),
              toInternalBalance: false
            }),
            limit,
            block.timestamp.add(600)
          );
      }


      // Get balance of token0
      uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
      // Provided that token0 quantity is > 0, redeposit
      if (token0Amt > 0) {
          // Increase the allowance of the AcryptosVault to spend token0 (for deposit)
          IERC20(token0Address).safeIncreaseAllowance(
              wantAddress,
              token0Amt
          );
          // Re-deposit the newly swapped token0 to get new Want tokens minted
          IAcryptosVault(wantAddress).deposit(token0Amt);
      }

      // Update last earned block
      lastEarnBlock = block.number;

      // Farm Want tokens obtained
      _farm();
  }

  /// @notice Calculates exchange rate of Token0 per Earned token. Note: Ignores swap fees!
  /// @return exhange rate of Token0 per Earned token
  function getExchangeRateEarnedToToken0() internal returns (uint256) {
    // Calculate current balances of each token (Earned, and token0)
    (uint256 cashEarned, , , ) = 
      IBalancerVault(balancerVaultAddress).getPoolTokenInfo(balancerPoolEarnedToToken0, IERC20(earnedAddress));
    (uint256 cashToken0, , , ) = 
      IBalancerVault(balancerVaultAddress).getPoolTokenInfo(balancerPoolEarnedToToken0, IERC20(token0Address));
    // Return exchange rate, accounting for weightings
    return (cashToken0.div(balancerPoolToken0WeightBasisPoints)).div(cashEarned.div(balancerPoolEarnedWeightBasisPoints));
  }
}
