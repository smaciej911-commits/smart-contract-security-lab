// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./VulnerableProtocol.sol";

interface IIndependentPriceOracle {
    function collateralPrice() external view returns (uint256);
}

/// @dev Test oracle representing a delayed/TWAP or independently sourced feed.
/// It is deliberately disconnected from the spot pool used by the exploit.
contract FixedPriceOracle is IIndependentPriceOracle {
    uint256 public immutable override collateralPrice;

    constructor(uint256 initialPrice) {
        require(initialPrice != 0, "zero oracle price");
        collateralPrice = initialPrice;
    }
}

/// @dev Mutable feed used only by invariant handlers to model market price changes.
contract MutableTestPriceOracle is IIndependentPriceOracle {
    error NotController();
    error InvalidPrice();

    uint256 public override collateralPrice;
    address public controller;

    constructor(uint256 initialPrice) {
        if (initialPrice == 0) revert InvalidPrice();
        collateralPrice = initialPrice;
        controller = msg.sender;
    }

    function transferControl(address newController) external {
        if (msg.sender != controller) revert NotController();
        require(newController != address(0), "zero controller");
        controller = newController;
    }

    function setPrice(uint256 newPrice) external {
        if (msg.sender != controller) revert NotController();
        if (newPrice == 0) revert InvalidPrice();
        collateralPrice = newPrice;
    }
}

contract FixedOracleLending is IOracleLending {
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InvalidConfiguration();
    error InvalidAmount();
    error InvalidPrice();
    error Reentrancy();
    error RepayExceedsDebt();
    error PositionHealthy();

    uint256 private constant MAX_LTV_BPS = 10_000;

    IERC20OracleLab public immutable collateralToken;
    IERC20OracleLab public immutable quoteToken;
    IIndependentPriceOracle public immutable oracle;
    uint256 public immutable ltvBps;
    uint256 public totalDebt;
    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;
    bool private entered;

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    constructor(
        IERC20OracleLab collateral,
        IERC20OracleLab quote,
        IIndependentPriceOracle priceOracle,
        uint256 loanToValueBps
    ) {
        if (
            address(collateral) == address(0) || address(quote) == address(0) || address(priceOracle) == address(0)
                || loanToValueBps == 0 || loanToValueBps > MAX_LTV_BPS
        ) revert InvalidConfiguration();
        collateralToken = collateral;
        quoteToken = quote;
        oracle = priceOracle;
        ltvBps = loanToValueBps;
    }

    function depositCollateral(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "collateral transfer failed");
        collateralOf[msg.sender] += amount;
    }

    function borrow(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 collateralValue = collateralOf[msg.sender] * _price() / 1e18;
        if (debtOf[msg.sender] + amount > collateralValue * ltvBps / 10_000) revert InsufficientCollateral();
        if (quoteToken.balanceOf(address(this)) < amount) revert InsufficientLiquidity();

        debtOf[msg.sender] += amount;
        totalDebt += amount;
        require(quoteToken.transfer(msg.sender, amount), "quote transfer failed");
    }

    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 debt = debtOf[msg.sender];
        if (amount > debt) revert RepayExceedsDebt();
        require(quoteToken.transferFrom(msg.sender, address(this), amount), "repayment transfer failed");
        debtOf[msg.sender] = debt - amount;
        totalDebt -= amount;
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        uint256 collateral = collateralOf[msg.sender];
        if (amount == 0 || amount > collateral) revert InvalidAmount();
        uint256 remainingValue = (collateral - amount) * _price() / 1e18;
        if (debtOf[msg.sender] > remainingValue * ltvBps / 10_000) revert InsufficientCollateral();
        collateralOf[msg.sender] = collateral - amount;
        require(collateralToken.transfer(msg.sender, amount), "collateral transfer failed");
    }

    function liquidate(address borrower, uint256 repayAmount) external nonReentrant {
        uint256 price = _price();
        uint256 collateralValue = collateralOf[borrower] * price / 1e18;
        if (debtOf[borrower] <= collateralValue * ltvBps / 10_000) revert PositionHealthy();
        if (repayAmount == 0 || repayAmount > debtOf[borrower]) revert RepayExceedsDebt();

        require(quoteToken.transferFrom(msg.sender, address(this), repayAmount), "repayment transfer failed");
        debtOf[borrower] -= repayAmount;
        totalDebt -= repayAmount;
        uint256 seized = repayAmount * 1e18 / price * 10_500 / 10_000;
        if (seized > collateralOf[borrower]) seized = collateralOf[borrower];
        collateralOf[borrower] -= seized;
        require(collateralToken.transfer(msg.sender, seized), "seizure transfer failed");
    }

    function _price() private view returns (uint256 price) {
        price = oracle.collateralPrice();
        if (price == 0) revert InvalidPrice();
    }
}
