// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MoneyCanBuyToken} from "src/MoneyCanBuyToken.sol";

/// @dev Makes an actual intermediate call so token authorization must use msg.sender, not tx.origin.
contract TokenCaller {
    function transfer(MoneyCanBuyToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function approve(MoneyCanBuyToken token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transferFrom(MoneyCanBuyToken token, address from, address to, uint256 amount)
        external
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }
}

/// @notice Regression cases for authorization boundaries and accounting across multiple operations.
/// forge-config: default.fuzz.runs = 1000
contract MoneyCanBuyTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    MoneyCanBuyToken internal token;

    function setUp() public {
        token = new MoneyCanBuyToken();
    }

    function test_oneBaseUnitCanMakeARoundTripWithoutDust() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillChecksAvailableBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(address(this), SUPPLY + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferCannotBypassBalanceCheck() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 11);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 11);
        assertEq(token.allowance(ALICE, SPENDER), 11);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_spenderCanReceiveTheEntireSupplyWithExactApproval() public {
        token.approve(SPENDER, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), SPENDER, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(SPENDER), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_unlimitedAllowanceDoesNotPermitOverspendingBalance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_replacingUnlimitedApprovalWithFiniteAmountLimitsSpender() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 7);
        assertTrue(token.approve(SPENDER, 7));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 7, 8)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 8);
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.balanceOf(ALICE), 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 7));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 7);
    }

    function test_revokeUnlimitedApprovalPreservesHolderControl() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(ALICE, SPENDER, 0);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 9);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 9));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_refillingBalanceDoesNotRestoreSpentAllowance() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 10));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        token.transfer(ALICE, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_directTransferDoesNotConsumeOrCancelAllowance() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10));
        assertEq(token.allowance(ALICE, SPENDER), 10);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 10));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 10));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 10);
    }

    function test_approvedSpenderCannotDelegateAnotherOwnersAllowance() public {
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        assertTrue(token.approve(BOB, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.allowance(address(this), BOB), 0);
        assertEq(token.allowance(SPENDER, BOB), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_zeroDelegatedTransferPreservesFiniteAndInfiniteApprovals() public {
        uint256[2] memory approvals = [uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(ALICE);
            token.approve(SPENDER, approvals[i]);
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(ALICE, BOB, 0);
            vm.prank(SPENDER);
            assertTrue(token.transferFrom(ALICE, BOB, 0));
            assertEq(token.allowance(ALICE, SPENDER), approvals[i]);
            assertEq(token.balanceOf(ALICE), 0);
            assertEq(token.balanceOf(BOB), 0);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferStillRejectsZeroReceiver() public {
        uint256[3] memory approvals = [uint256(0), uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            token.approve(SPENDER, approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(SPENDER);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), SPENDER), approvals[i]);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        token.approve(SPENDER, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_contractTransferCannotSpendTransactionOriginsBalance() public {
        TokenCaller caller = new TokenCaller();
        token.transfer(ALICE, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(caller), 0, 1)
        );
        vm.prank(ALICE, ALICE);
        caller.transfer(token, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);

        token.transfer(address(caller), 1);
        vm.prank(ALICE, ALICE);
        assertTrue(caller.transfer(token, BOB, 1));
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_contractSpenderCannotUseTransactionOriginsApproval() public {
        TokenCaller caller = new TokenCaller();
        token.approve(ALICE, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(caller), 0, 1)
        );
        vm.prank(ALICE, ALICE);
        caller.transferFrom(token, address(this), BOB, 1);
        assertEq(token.allowance(address(this), ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);

        token.approve(address(caller), 1);
        vm.prank(ALICE, ALICE);
        assertTrue(caller.transferFrom(token, address(this), BOB, 1));
        assertEq(token.allowance(address(this), address(caller)), 0);
        assertEq(token.allowance(address(this), ALICE), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_contractApprovalBelongsToContractNotTransactionOrigin() public {
        TokenCaller caller = new TokenCaller();
        token.transfer(address(caller), 10);
        vm.prank(ALICE, ALICE);
        assertTrue(caller.approve(token, SPENDER, 10));
        assertEq(token.allowance(address(caller), SPENDER), 10);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(caller), BOB, 10));
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.allowance(address(caller), SPENDER), 0);
    }

    function testFuzz_delegatedBalanceFailurePreservesAllowance(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 approvalSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approved = bound(approvalSeed, amount, type(uint256).max);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidReceiverPreservesAllowance(uint256 amountSeed, uint256 approvalSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 approved = bound(approvalSeed, amount, type(uint256).max);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_cumulativeSpendCannotExceedApproval(uint256 approvalSeed, uint256 firstSeed) public {
        uint256 approved = bound(approvalSeed, 1, SUPPLY - 1);
        uint256 first = bound(firstSeed, 0, approved);
        uint256 remaining = approved - first;
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), remaining);

        // There is enough balance for this call; only the cumulative allowance forbids it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, remaining, remaining + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, remaining + 1);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(address(this), SPENDER), remaining);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, remaining));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), remaining);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripPreservesBalancesAndApprovals(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 aliceApproval,
        uint256 bobApproval
    ) public {
        uint256 aliceBalance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, 0, aliceBalance);
        token.transfer(ALICE, aliceBalance);
        token.transfer(BOB, SUPPLY - aliceBalance);
        vm.prank(ALICE);
        token.approve(SPENDER, aliceApproval);
        vm.prank(BOB);
        token.approve(SPENDER, bobApproval);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), aliceBalance - amount);
        assertEq(token.balanceOf(BOB), SUPPLY - aliceBalance + amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(token.balanceOf(BOB), SUPPLY - aliceBalance);
        assertEq(token.allowance(ALICE, SPENDER), aliceApproval);
        assertEq(token.allowance(BOB, SPENDER), bobApproval);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransfersMatchSingleSpend(
        uint256 firstSeed,
        uint256 secondSeed,
        bool infinite
    ) public {
        MoneyCanBuyToken singleSpend = new MoneyCanBuyToken();
        uint256 first = bound(firstSeed, 0, SUPPLY);
        uint256 second = bound(secondSeed, 0, SUPPLY - first);
        uint256 approved = infinite ? type(uint256).max : first + second;
        token.approve(SPENDER, approved);
        singleSpend.approve(SPENDER, approved);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertTrue(token.transferFrom(address(this), ALICE, second));
        assertTrue(singleSpend.transferFrom(address(this), ALICE, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), singleSpend.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), singleSpend.balanceOf(address(this)));
        assertEq(token.allowance(address(this), SPENDER), singleSpend.allowance(address(this), SPENDER));
        assertEq(token.balanceOf(ALICE), first + second);
        assertEq(token.allowance(address(this), SPENDER), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleSpend.totalSupply(), SUPPLY);
    }
}
