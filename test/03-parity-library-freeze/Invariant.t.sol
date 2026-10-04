// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/03-parity-library-freeze/FixedProtocol.sol";

contract ParityLibraryHandler {
    ParityWalletLibraryFixed private immutable implementation;

    constructor(ParityWalletLibraryFixed libraryImplementation) {
        implementation = libraryImplementation;
    }

    function attemptDirectInitialization(uint256 fuzzOwner) external {
        address[] memory owners = new address[](1);
        owners[0] = address(uint160(fuzzOwner));
        (bool success,) =
            address(implementation).call(abi.encodeCall(ParityWalletLibraryFixed.initWallet, (owners, 1, 0)));
        require(!success, "implementation accepted a second initialization");
    }

    function attemptRemovedKill(uint256 fuzzRecipient) external {
        (bool success,) =
            address(implementation).call(abi.encodeWithSignature("kill(address)", address(uint160(fuzzRecipient))));
        require(!success, "shared implementation accepted a kill call");
    }
}

contract ParityLibraryInvariantTest {
    ParityWalletLibraryFixed private implementation;
    ParityLibraryHandler private handler;

    function setUp() external {
        implementation = new ParityWalletLibraryFixed();
        handler = new ParityLibraryHandler(implementation);
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_SharedImplementationStaysInitialized() external view {
        require(implementation.isInitialized(), "implementation became initializable");
        require(implementation.numberOfOwners() == 1, "implementation owner-count sentinel changed");
    }

    function invariant_SharedImplementationHasNoOwner() external view {
        require(implementation.primaryOwner() == address(0), "direct call changed implementation ownership");
    }
}
