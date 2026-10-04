// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/02-share-price-inflation/VulnerableProtocol.sol";
import "../../src/02-share-price-inflation/FixedProtocol.sol";

contract VaultHandler {
    VaultLabToken private immutable asset;
    DonationVaultFixed private immutable vault;

    constructor(VaultLabToken underlyingAsset, DonationVaultFixed targetVault) {
        asset = underlyingAsset;
        vault = targetVault;
        asset.approve(address(targetVault), type(uint256).max);
    }

    function deposit(uint256 fuzzAmount) external {
        uint256 amount = fuzzAmount % (1 ether) + 1;
        if (vault.previewDeposit(amount) == 0) return;
        asset.mint(address(this), amount);
        vault.deposit(amount, address(this));
    }

    function donate(uint256 fuzzAmount) external {
        uint256 amount = fuzzAmount % (1 ether + 1);
        if (amount == 0) return;
        asset.mint(address(this), amount);
        require(asset.transfer(address(vault), amount), "donation transfer failed");
    }

    function redeem(uint256 fuzzShares) external {
        uint256 sharesOwned = vault.balanceOf(address(this));
        if (sharesOwned == 0) return;
        uint256 shares = fuzzShares % (sharesOwned + 1);
        if (shares == 0) return;
        vault.redeem(shares, address(this));
    }
}

contract DonationVaultInvariantTest {
    VaultLabToken private asset;
    DonationVaultFixed private vault;
    VaultHandler private handler;

    function setUp() external {
        asset = new VaultLabToken();
        vault = new DonationVaultFixed(asset);
        handler = new VaultHandler(asset, vault);
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_SupplyEqualsTheSumOfAllUserShares() external view {
        require(vault.totalSupply() == vault.balanceOf(address(handler)), "share supply is inconsistent");
    }

    function invariant_AllOutstandingSharesRemainAssetBacked() external view {
        require(vault.previewRedeem(vault.totalSupply()) <= vault.totalAssets(), "share claim exceeds assets");
    }
}
