// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

interface IPCSMasterChef {
    function pendingCake(uint256 _pid, address _user) external view returns (uint256);
    function poolLength() external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);
    function poolInfo(uint256 _i) external view returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accCakePerShare);

    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
}