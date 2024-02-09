// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import "./mocks/MyERC20.sol";

contract MyERC20Test is Test {
    MyERC20 myErc20;

    function setUp() public {
        myErc20 = new MyERC20("Nice");
        console.log(address(myErc20));
    }

    function test1() public {
        assertEq(myErc20.name(), "Nice");
    }

    function test2() public {
        assertEq(myErc20.symbol(), "SYM");
    }
}
