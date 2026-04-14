// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {HomeTransaction} from "../src/HomeTransaction.sol";

contract FactoryTest is Test {
    Factory internal factory;
    address payable internal seller;
    address payable internal buyer;

    function setUp() public {
        factory = new Factory();
        seller = payable(makeAddr("seller"));
        buyer = payable(makeAddr("buyer"));
    }

    function test_Create_StoresInstanceAndIncrementsCount() public {
        assertEq(factory.getInstanceCount(), 0);

        HomeTransaction h = factory.create(
            "1 Main St", "12345", "Townville",
            5 ether, 100 ether,
            seller, buyer
        );

        assertEq(factory.getInstanceCount(), 1);
        assertEq(address(factory.getInstance(0)), address(h));
        assertEq(h.realtor(), address(this));
        assertEq(h.seller(), seller);
        assertEq(h.buyer(), buyer);
        assertEq(h.price(), 100 ether);
        assertEq(h.realtorFee(), 5 ether);
    }

    function test_Create_TracksMultipleInstances() public {
        factory.create("a", "1", "x", 1 ether, 10 ether, seller, buyer);
        factory.create("b", "2", "y", 1 ether, 10 ether, seller, buyer);
        factory.create("c", "3", "z", 1 ether, 10 ether, seller, buyer);

        assertEq(factory.getInstanceCount(), 3);
        HomeTransaction[] memory all = factory.getInstances();
        assertEq(all.length, 3);
    }

    function test_GetInstance_RevertsOutOfRange() public {
        vm.expectRevert("index out of range");
        factory.getInstance(0);
    }
}
