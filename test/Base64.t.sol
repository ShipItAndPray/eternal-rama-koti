// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {Base64} from "../src/lib/Base64.sol";

contract Base64Test is Test {
    function test_matchesCheatcode() public pure {
        bytes memory a = "";
        bytes memory b = "f";
        bytes memory c = "fo";
        bytes memory d = unicode"శ్రీరామ";
        bytes memory e = hex"00ff10ee2000";
        assertEq(Base64.encode(a), vm.toBase64(a));
        assertEq(Base64.encode(b), vm.toBase64(b));
        assertEq(Base64.encode(c), vm.toBase64(c));
        assertEq(Base64.encode(d), vm.toBase64(d));
        assertEq(Base64.encode(e), vm.toBase64(e));
    }
    function testFuzz_matchesCheatcode(bytes memory x) public pure {
        assertEq(Base64.encode(x), vm.toBase64(x));
    }
}
