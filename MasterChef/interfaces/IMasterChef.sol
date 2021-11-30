//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.12;

interface IMasterChef {
    function updatePool(
        uint256 _pid
        ) external;
    
    function deposit(
        uint256 _pid, 
        uint256 _amount, 
        address _referrer
        ) external;
        
    function withdraw(
        uint256 _pid, 
        uint256 _amount
        ) external;
        
    function emergencyWithdraw(
        uint256 _pid
        ) external;
}