// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {DataStore} from "../src/lib/DataStore.sol";

contract DataStoreTest is Test {
    function test_roundTrip() public {
        bytes memory d = bytes(vm.readFile("glyphs/0.txt"));
        address p = DataStore.put(d);
        assertEq(DataStore.get(p), d);
        assertEq(p.code.length, d.length + 1);
        assertEq(uint8(p.code[0]), 0);
    }
    function testFuzz_roundTrip(bytes memory d) public {
        vm.assume(d.length < 24_000);
        assertEq(DataStore.get(DataStore.put(d)), d);
    }
}
