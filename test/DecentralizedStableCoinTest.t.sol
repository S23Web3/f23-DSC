//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    address USER = makeAddr("USER");
    uint256 constant STARTING_BALANCE = 10 ether;

    function setUp() public {
        // deploy a new DSC contract
        // deal the user some funds
    }

    function testSuccessfulBurn() public {
        // Simulate a user
        uint256 amountToBurn = 1; // Burn 1 starting balance
        vm.prank(USER);
        // Check that balance is sufficient and more than the amount to burn
        assert(dsc.balanceOf(USER) > amountToBurn);

        // Burn tokens
        dsc.burn(amountToBurn);

        // Check that user's balance has been reduced
        assertEq(dsc.balanceOf(USER), STARTING_BALANCE - amountToBurn);
    }

    function testFailBurnZeroTokens() public {
        // Simulate a user
        vm.prank(USER);
        vm.deal(USER, STARTING_BALANCE);
        uint256 amountToBurn = 0;

        // Attempt to burn zero tokens
        vm.expectRevert("DecentralizedStableCoin__MustBeMoreThanZero");
        dsc.burn(amountToBurn);
    }
}
