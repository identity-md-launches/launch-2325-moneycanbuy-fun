// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MoneyCanBuyToken} from "../src/MoneyCanBuyToken.sol";
import {LaunchHarness, TokenHolder, RejectingRecipient} from "./helpers/LaunchHarness.sol";

contract MoneyCanBuyTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    MoneyCanBuyToken internal token;

    function setUp() public {
        token = new MoneyCanBuyToken();
    }

    function test_metadataAndEntireSupply() public view {
        assertEq(token.name(), "MoneyCanBuy.fun");
        assertEq(token.symbol(), "YOLO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        MoneyCanBuyToken deployed = new MoneyCanBuyToken();
        assertEq(deployed.balanceOf(address(this)), SUPPLY);
    }

    function test_factoryReceivesSupplyInsteadOfFactoryCaller() public {
        LaunchHarness factory = new LaunchHarness();
        vm.prank(ALICE);
        MoneyCanBuyToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_create2DeploymentReceivesFullSupply() public {
        LaunchHarness factory = new LaunchHarness();
        MoneyCanBuyToken deployed = factory.deployDeterministically(keccak256("YOLO test deployment"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertGt(address(deployed).code.length, 0);
        assertLe(address(deployed).code.length, 24_576);
        assertLe(type(MoneyCanBuyToken).creationCode.length, 49_152);
    }

    function test_launchAllocationClaimsAndHolderTransfersArriveWhole() public {
        LaunchHarness factory = new LaunchHarness();
        TokenHolder distributor = new TokenHolder();
        TokenHolder poolHolder = new TokenHolder();
        MoneyCanBuyToken deployed = factory.deploy();
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY / 10;

        factory.send(deployed, address(distributor), swarm);
        factory.send(deployed, address(poolHolder), pool);
        factory.send(deployed, ALICE, remainder);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(address(distributor)), swarm);
        assertEq(deployed.balanceOf(address(poolHolder)), pool);
        assertEq(deployed.balanceOf(ALICE), remainder);

        distributor.send(deployed, BOB, swarm);
        assertEq(deployed.balanceOf(address(distributor)), 0);
        assertEq(deployed.balanceOf(BOB), swarm);

        poolHolder.send(deployed, ALICE, 42 ether);
        assertEq(deployed.balanceOf(ALICE), remainder + 42 ether);
        vm.prank(ALICE);
        assertTrue(deployed.transfer(address(poolHolder), 42 ether));
        assertEq(deployed.balanceOf(address(poolHolder)), pool);
        assertEq(deployed.balanceOf(ALICE), remainder);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotInvokeRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_transferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyHolderCannotTransferOneUnit() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferMaximumUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalEmitsEventOverwritesAndRevokes() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 25));
        assertEq(token.allowance(address(this), SPENDER), 25);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_approvalIsIsolatedByOwnerAndSpender() public {
        token.approve(SPENDER, 20);
        vm.prank(ALICE);
        token.approve(SPENDER, 30);
        assertEq(token.allowance(address(this), SPENDER), 20);
        assertEq(token.allowance(ALICE, SPENDER), 30);
        assertEq(token.allowance(address(this), BOB), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_transferFromDecrementsAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 40);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.allowance(address(this), SPENDER), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.balanceOf(ALICE), 40);
    }

    function test_exactAllowanceCanOnlyBeSpentOnce() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 100));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_infiniteAllowanceIsNotDecreased() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10));
        assertTrue(token.transferFrom(address(this), BOB, 20));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30);
    }

    function test_selfTransferFromStillConsumesFiniteAllowance() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_transferFromByHolderStillRequiresAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroSenderReverts() public {
        // Allowance spending validates the approver before _transfer validates its sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_transferFromZeroReceiverRollsBackAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 50);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_insufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 50));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 50);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_deployerHasNoAllowancePrivilege() public {
        token.transfer(ALICE, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10);
    }

    function test_noMintBurnAdminOrUpgradeEntrypoints() public {
        token.transfer(ALICE, 100);
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[10] = abi.encodeWithSignature("setOwner(address)", BOB);
        calls[11] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[12] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[13] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[15] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[16] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(BOB);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function testFuzz_transferConservesBalances(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferCannotCreateTokens(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
            )
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_approveAcceptsFullUintRange(uint256 amount) public {
        assertTrue(token.approve(SPENDER, amount));
        assertEq(token.allowance(address(this), SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_finiteAllowanceSpend(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, type(uint256).max - 1);
        uint256 amount = bound(rawAmount, 0, approved < SUPPLY ? approved : SUPPLY);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowanceOverdrawReverts(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = approved + bound(rawExcess, 1, SUPPLY - approved);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
