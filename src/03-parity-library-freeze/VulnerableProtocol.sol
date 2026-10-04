// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IHistoricalParityLibrary {
    function initWallet(address[] calldata owners, uint256 required, uint256 dailyLimit) external;
    function isOwner(address candidate) external view returns (bool);
    function kill(address payable recipient) external;
}
