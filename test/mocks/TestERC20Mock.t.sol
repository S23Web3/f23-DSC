//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

contract TestERC20Mock is Test {
    ERC20Mock token;
    address alice;
    address bob;

    function setUp() public {
        token = new ERC20Mock("MockToken", "MTK", msg.sender, 1000);
        alice = address(0x123);
        bob = address(0x456);
    }

    function testInitialBalance() public {
        assertEq(token.balanceOf(msg.sender), 1000);
    }

    function testMint() public {
        uint256 initialSupply = token.totalSupply();
        uint256 mintAmount = 1000;

        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
    }

    function testBurn() public {
        token.burn(msg.sender, 200);
        assertEq(token.balanceOf(msg.sender), 800);
        assertEq(token.totalSupply(), 800);
    }

    function testTransferInternal() public {
        token.transferInternal(msg.sender, bob, 100);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.balanceOf(msg.sender), 900);
    }

    function testApproveInternal() public {
        token.approveInternal(msg.sender, alice, 50);
        assertEq(token.allowance(msg.sender, alice), 50);
    }
}
