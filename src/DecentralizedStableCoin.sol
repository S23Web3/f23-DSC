// SPDX-License-Identifier: MIT

// layout
// version
// imports
// errors
// interfaces libraries contracts
// type declarations
// state variables
// events
// modifiers
// functions

// in functions
//     constructor
//     receive if exists
//     fallback if exists
// externalpublic
// internalprivate
// view/pure
pragma solidity ^0.8.18;

//due to issues decided not to do remapping, later investigate what the root cause is
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

error DecentralizedStableCoin__MustBeMoreThanZero();
error DecentralizedStableCoin__BurnAmountExceedsBalance();
error DecentralizedStableCoin__NotZeroAddress();

/*
 * @title DecentralizedStableCoin 
 * @author Malik the Amsterdamse
 * Collateral Exogenous (BTC/ETH)
 * Pegged to USD, helped by the burn function to maintain the price
 * Governed by the DecentralizedStableCoinEngine
*/

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        //using burn function from parent class ERC20Burnable
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
