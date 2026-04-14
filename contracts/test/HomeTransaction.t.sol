// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HomeTransaction} from "../src/HomeTransaction.sol";

contract HomeTransactionTest is Test {
    HomeTransaction internal home;

    address payable internal realtor;
    address payable internal seller;
    address payable internal buyer;

    uint internal constant PRICE = 100 ether;
    uint internal constant REALTOR_FEE = 5 ether;
    uint internal constant MIN_DEPOSIT = 10 ether; // 10% of PRICE

    function setUp() public {
        realtor = payable(makeAddr("realtor"));
        seller = payable(makeAddr("seller"));
        buyer = payable(makeAddr("buyer"));

        home = new HomeTransaction(
            "1 Main St",
            "12345",
            "Townville",
            REALTOR_FEE,
            PRICE,
            realtor,
            seller,
            buyer
        );

        vm.deal(buyer, 1_000 ether);
    }

    function _advanceToReview() internal {
        vm.prank(seller);
        home.sellerSignContract();

        vm.prank(buyer);
        home.buyerSignContractAndPayDeposit{value: MIN_DEPOSIT}();
    }

    function _advanceToFinalization() internal {
        _advanceToReview();
        vm.prank(realtor);
        home.realtorReviewedClosingConditions(true);
    }

    function test_HappyPath_PaysSellerAndRealtor() public {
        _advanceToFinalization();

        uint sellerBefore = seller.balance;
        uint realtorBefore = realtor.balance;

        vm.prank(buyer);
        home.buyerFinalizeTransaction{value: PRICE - MIN_DEPOSIT}();

        assertEq(uint(home.contractState()), uint(HomeTransaction.ContractState.Finalized));
        assertEq(seller.balance - sellerBefore, PRICE - REALTOR_FEE);
        assertEq(realtor.balance - realtorBefore, REALTOR_FEE);
        assertEq(address(home).balance, 0);
    }

    function test_RealtorRejection_RefundsBuyer() public {
        _advanceToReview();

        uint buyerBefore = buyer.balance;

        vm.prank(realtor);
        home.realtorReviewedClosingConditions(false);

        assertEq(uint(home.contractState()), uint(HomeTransaction.ContractState.Rejected));
        assertEq(buyer.balance - buyerBefore, MIN_DEPOSIT);
        assertEq(address(home).balance, 0);
    }

    function test_BuyerCancel_ForfeitsDepositToSellerAndRealtor() public {
        _advanceToFinalization();

        uint sellerBefore = seller.balance;
        uint realtorBefore = realtor.balance;

        vm.prank(buyer);
        home.cancelAndForfeitDeposit();

        assertEq(uint(home.contractState()), uint(HomeTransaction.ContractState.Rejected));
        assertEq(realtor.balance - realtorBefore, REALTOR_FEE);
        assertEq(seller.balance - sellerBefore, MIN_DEPOSIT - REALTOR_FEE);
    }

    function test_AnyoneCanCancel_AfterDeadline() public {
        _advanceToFinalization();

        vm.warp(block.timestamp + 6 minutes);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        home.cancelAndForfeitDeposit();

        assertEq(uint(home.contractState()), uint(HomeTransaction.ContractState.Rejected));
    }

    function test_StrangerCancelBeforeDeadline_Reverts() public {
        _advanceToFinalization();

        vm.prank(makeAddr("stranger"));
        vm.expectRevert("Only buyer can cancel before transaction deadline");
        home.cancelAndForfeitDeposit();
    }

    // Regression test for the underflow fix: when realtorFee exceeds the
    // deposit, cancelling must not revert and must clamp the realtor payout
    // to whatever was actually deposited.
    function test_Cancel_DoesNotUnderflow_WhenFeeExceedsDeposit() public {
        HomeTransaction h = new HomeTransaction(
            "1 Main", "1", "X",
            15 ether, // realtor fee > min deposit (10 ether)
            100 ether,
            realtor,
            seller,
            buyer
        );

        vm.prank(seller);
        h.sellerSignContract();

        vm.prank(buyer);
        h.buyerSignContractAndPayDeposit{value: 10 ether}();

        vm.prank(realtor);
        h.realtorReviewedClosingConditions(true);

        uint realtorBefore = realtor.balance;
        uint sellerBefore = seller.balance;

        vm.prank(buyer);
        h.cancelAndForfeitDeposit();

        assertEq(realtor.balance - realtorBefore, 10 ether);
        assertEq(seller.balance - sellerBefore, 0);
        assertEq(address(h).balance, 0);
    }

    function test_Constructor_RevertsIfPriceLessThanFee() public {
        vm.expectRevert("Price needs to be more than realtor fee!");
        new HomeTransaction("a", "b", "c", 100 ether, 50 ether, realtor, seller, buyer);
    }

    function test_OnlySellerCanSign() public {
        vm.prank(buyer);
        vm.expectRevert("Only seller can sign contract");
        home.sellerSignContract();
    }

    function test_BuyerSign_RevertsBelowMinimumDeposit() public {
        vm.prank(seller);
        home.sellerSignContract();

        vm.prank(buyer);
        vm.expectRevert("Buyer needs to deposit between 10% and 100% to sign contract");
        home.buyerSignContractAndPayDeposit{value: 1 ether}();
    }

    function test_BuyerFinalize_RevertsOnWrongAmount() public {
        _advanceToFinalization();

        vm.prank(buyer);
        vm.expectRevert("Buyer needs to pay the rest of the cost to finalize transaction");
        home.buyerFinalizeTransaction{value: 1 ether}();
    }

    function test_StateMachine_RejectsOutOfOrderCalls() public {
        vm.prank(buyer);
        vm.expectRevert("Wrong contract state");
        home.buyerSignContractAndPayDeposit{value: MIN_DEPOSIT}();
    }
}
