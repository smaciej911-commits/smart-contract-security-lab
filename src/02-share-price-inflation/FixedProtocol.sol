// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./VulnerableProtocol.sol";

/// @dev Minimal mitigation model using virtual assets/shares and explicit round-down conversion.
/// A production ERC-4626 vault should use audited full-precision math and the standard's exact API.
contract DonationVaultFixed {
    error InvalidConfiguration();
    error Reentrancy();

    uint256 public constant VIRTUAL_ASSETS = 1;
    uint256 public constant VIRTUAL_SHARES = 1e6;

    IERC20VaultLab public immutable asset;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    bool private entered;

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor(IERC20VaultLab underlyingAsset) {
        if (address(underlyingAsset) == address(0)) revert InvalidConfiguration();
        asset = underlyingAsset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return shares * (totalAssets() + VIRTUAL_ASSETS) / (totalSupply + VIRTUAL_SHARES);
    }

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        require(assets != 0, "zero deposit");
        shares = previewDeposit(assets); // round down; virtual offsets keep the first deposit meaningful
        require(shares != 0, "deposit rounds to zero");

        require(asset.transferFrom(msg.sender, address(this), assets), "asset transfer failed");
        totalSupply += shares;
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        uint256 userShares = balanceOf[msg.sender];
        require(shares != 0 && shares <= userShares, "invalid shares");
        assets = previewRedeem(shares); // round down so the vault never pays more than the share claim

        balanceOf[msg.sender] = userShares - shares;
        totalSupply -= shares;
        require(asset.transfer(receiver, assets), "asset transfer failed");
    }
}
