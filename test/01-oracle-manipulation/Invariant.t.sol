// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/01-oracle-manipulation/VulnerableProtocol.sol";
import "../../src/01-oracle-manipulation/FixedProtocol.sol";

/// @dev Fuzzer adapter: invalid borrow/withdraw amounts are classified; price drops trigger liquidation.
contract LendingHandler {
    OracleLabToken private immutable collateral;
    OracleLabToken private immutable quote;
    FixedOracleLending private immutable lending;
    MutableTestPriceOracle private immutable oracle;

    constructor(
        OracleLabToken collateralToken,
        OracleLabToken quoteToken,
        FixedOracleLending protocol,
        MutableTestPriceOracle priceOracle
    ) {
        collateral = collateralToken;
        quote = quoteToken;
        lending = protocol;
        oracle = priceOracle;
        collateral.approve(address(protocol), type(uint256).max);
        quote.approve(address(protocol), type(uint256).max);
    }

    function deposit(uint256 fuzzAmount) external {
        uint256 amount = fuzzAmount % (1_000 ether) + 1;
        collateral.mint(address(this), amount);
        lending.depositCollateral(amount);
    }

    function borrow(uint256 fuzzAmount) external {
        uint256 amount = fuzzAmount % (1_000 ether) + 1;
        (bool success, bytes memory result) = address(lending).call(abi.encodeCall(FixedOracleLending.borrow, (amount)));
        if (!success) {
            _requireExpectedError(
                result,
                FixedOracleLending.InsufficientCollateral.selector,
                FixedOracleLending.InsufficientLiquidity.selector
            );
        }
    }

    function repay(uint256 fuzzAmount) external {
        uint256 debt = lending.debtOf(address(this));
        if (debt == 0) return;
        uint256 amount = fuzzAmount % (debt + 1);
        if (amount == 0) return;

        quote.mint(address(this), amount);
        lending.repay(amount);
    }

    function withdraw(uint256 fuzzAmount) external {
        uint256 collateralAmount = lending.collateralOf(address(this));
        if (collateralAmount == 0) return;
        uint256 amount = fuzzAmount % (collateralAmount + 1);
        if (amount == 0) return;

        (bool success, bytes memory result) =
            address(lending).call(abi.encodeCall(FixedOracleLending.withdrawCollateral, (amount)));
        if (!success) {
            _requireExpectedError(result, FixedOracleLending.InsufficientCollateral.selector, bytes4(0));
        }
    }

    function changePrice(uint256 fuzzPrice) external {
        uint256 newPrice = fuzzPrice % (2_000 ether) + 1 ether;
        oracle.setPrice(newPrice);
        _liquidateIfNeeded();
    }

    function liquidate() external {
        _liquidateIfNeeded();
    }

    function _liquidateIfNeeded() private {
        uint256 debt = lending.debtOf(address(this));
        if (debt == 0) return;

        uint256 collateralValue = lending.collateralOf(address(this)) * oracle.collateralPrice() / 1e18;
        if (debt <= collateralValue * lending.ltvBps() / 10_000) return;

        quote.mint(address(this), debt);
        lending.liquidate(address(this), debt);
    }

    function _requireExpectedError(bytes memory result, bytes4 expected, bytes4 alternative) private pure {
        bytes4 actual;
        if (result.length >= 4) {
            assembly {
                actual := mload(add(result, 32))
            }
        }
        require(actual == expected || (alternative != bytes4(0) && actual == alternative), "unexpected lending failure");
    }
}

contract OracleLendingInvariantTest {
    uint256 private constant BAD_DEBT_TOLERANCE = 0;

    FixedOracleLending private lending;
    OracleLabToken private collateral;
    OracleLabToken private quote;
    LendingHandler private handler;

    function setUp() external {
        collateral = new OracleLabToken("Collateral");
        quote = new OracleLabToken("Quote");
        MutableTestPriceOracle oracle = new MutableTestPriceOracle(1_000 ether);
        lending = new FixedOracleLending(collateral, quote, oracle, 7_000);
        quote.mint(address(lending), 1_000_000 ether);
        handler = new LendingHandler(collateral, quote, lending, oracle);
        oracle.transferControl(address(handler));
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_DebtStaysWithinTheCurrentOracleLimit() external view {
        uint256 collateralValue = lending.collateralOf(address(handler)) * lending.oracle().collateralPrice() / 1e18;
        uint256 maximumDebt = collateralValue * lending.ltvBps() / 10_000;
        require(lending.debtOf(address(handler)) <= maximumDebt, "debt exceeds fixed-oracle collateral limit");
    }

    function invariant_DepositedCollateralRemainsInProtocol() external view {
        require(
            collateral.balanceOf(address(lending)) >= lending.collateralOf(address(handler)),
            "collateral accounting exceeds custody"
        );
    }

    function invariant_LiabilitiesDoNotExceedMarkedProtocolAssets() external view {
        uint256 collateralValue = collateral.balanceOf(address(lending)) * lending.oracle().collateralPrice() / 1e18;
        uint256 protocolAssets = quote.balanceOf(address(lending)) + collateralValue;
        require(lending.totalDebt() <= protocolAssets + BAD_DEBT_TOLERANCE, "liabilities exceed protocol assets");
    }
}
