// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20VaultLab {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Test asset; unrestricted minting keeps fuzz handlers self-contained.
contract VaultLabToken is IERC20VaultLab {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address recipient, uint256 amount) external {
        balanceOf[recipient] += amount;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address owner, address recipient, uint256 amount) external override returns (bool) {
        uint256 approved = allowance[owner][msg.sender];
        require(approved >= amount, "allowance too low");
        allowance[owner][msg.sender] = approved - amount;
        _transfer(owner, recipient, amount);
        return true;
    }

    function _transfer(address owner, address recipient, uint256 amount) private {
        require(balanceOf[owner] >= amount, "balance too low");
        balanceOf[owner] -= amount;
        balanceOf[recipient] += amount;
    }
}

/// @dev Minimal ERC-4626-style vault with the vulnerable raw-balance exchange rate.
contract DonationVaultVulnerable {
    IERC20VaultLab public immutable asset;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20VaultLab underlyingAsset) {
        asset = underlyingAsset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets != 0, "zero deposit");
        uint256 supply = totalSupply;
        uint256 managedAssets = totalAssets();
        shares = supply == 0 ? assets : assets * supply / managedAssets;

        require(asset.transferFrom(msg.sender, address(this), assets), "asset transfer failed");
        totalSupply = supply + shares;
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 userShares = balanceOf[msg.sender];
        require(shares != 0 && shares <= userShares, "invalid shares");
        assets = shares * totalAssets() / totalSupply;

        balanceOf[msg.sender] = userShares - shares;
        totalSupply -= shares;
        require(asset.transfer(receiver, assets), "asset transfer failed");
    }
}
