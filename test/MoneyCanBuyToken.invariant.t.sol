// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MoneyCanBuyToken} from "../src/MoneyCanBuyToken.sol";

/// @dev All generated holders are tracked. Expected balances and approvals are independent of token storage.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 4;

    MoneyCanBuyToken public immutable token;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(MoneyCanBuyToken token_) {
        token = token_;
        expectedBalance[actor(0)] = SUPPLY;
    }

    function actor(uint256 seed) public pure returns (address) {
        return address(uint160(0x1000 + seed % ACTOR_COUNT));
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Mixes valid and invalid delegated transfers; expected reverts must preserve the entire model.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, SUPPLY + 1);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        if (approved < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
                )
            );
        } else if (balance < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
        }
        vm.prank(spender);
        bool success = token.transferFrom(owner, to, amount);
        if (approved >= amount && balance >= amount) {
            assertTrue(success);
            if (approved != type(uint256).max) expectedAllowance[owner][spender] = approved - amount;
            _move(owner, to, amount);
        }
    }

    /// @dev Ensures delegated transfers of nonzero balances occur even when random approvals do not match.
    function approveAndSpend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedAllowance[owner][spender] = infinite ? type(uint256).max : 0;
        _move(owner, to, amount);
    }

    function overspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function transferToZero(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = actor(ownerSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    function _move(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

contract MoneyCanBuyTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MoneyCanBuyToken internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new MoneyCanBuyToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actor(0), SUPPLY));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveAndSpend.selector;
        selectors[4] = TokenHandler.overspend.selector;
        selectors[5] = TokenHandler.transferToZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndEveryBalanceMatchModel() public view {
        uint256 total;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address account = handler.actor(i);
            uint256 held = token.balanceOf(account);
            assertEq(held, handler.expectedBalance(account));
            total += held;
        }
        assertEq(total, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allAllowancesMatchModel() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actor(i);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
