// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Patch model: lock the shared implementation's own storage and remove the destructive entry point.
/// A proxy using delegatecall has separate storage, where initialization remains available once.
contract ParityWalletLibraryFixed {
    error AlreadyInitialized();
    error InvalidConfiguration();

    // These first two slots model the legacy layout: required threshold, then owner count.
    uint256 public required;
    uint256 public numberOfOwners;
    address public primaryOwner;

    constructor() {
        numberOfOwners = 1; // seals only the shared implementation's storage
    }

    function initWallet(address[] calldata owners, uint256 requiredConfirmations, uint256) external {
        if (numberOfOwners != 0) revert AlreadyInitialized();
        if (owners.length == 0 || requiredConfirmations == 0 || requiredConfirmations > owners.length) {
            revert InvalidConfiguration();
        }

        required = requiredConfirmations;
        numberOfOwners = owners.length + 1;
        primaryOwner = msg.sender;
    }

    function isInitialized() external view returns (bool) {
        return numberOfOwners != 0;
    }

    function isOwner(address candidate) external view returns (bool) {
        return candidate == primaryOwner;
    }

    // There is intentionally no kill/selfdestruct entry point on the shared library.
}
