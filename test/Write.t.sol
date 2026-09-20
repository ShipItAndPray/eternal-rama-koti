// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";
import {Forms} from "../src/Forms.sol";
import {Helpers} from "./Helpers.sol";

contract WriteTest is Test {
    EternalRamaKoti k;
    address a = address(0xA11CE);
    address b = address(0xB0B);
    string constant TE = unicode"శ్రీరామ";

    function setUp() public { k = Helpers.deployKoti(); }

    function test_everyFormMints() public {
        for (uint8 i = 0; i < Forms.COUNT; i++) {
            vm.prank(a);
            uint256 id = k.write(Forms.form(i), "Srini");
            assertEq(id, i + 1);
            (address w, uint8 lang,, string memory nm, string memory form) = k.entry(id);
            assertEq(w, a); assertEq(lang, i); assertEq(nm, "Srini"); assertEq(form, Forms.form(i));
        }
        assertEq(k.count(), Forms.COUNT);
    }
    function test_nearMissReverts() public {
        vm.expectRevert(EternalRamaKoti.UnknownForm.selector);
        k.write(unicode"శ్రీరామ ", "Srini");
        vm.expectRevert(EternalRamaKoti.UnknownForm.selector);
        k.write("sri rama", "Srini");
        vm.expectRevert(EternalRamaKoti.UnknownForm.selector);
        k.write("", "Srini");
    }
    function test_counters() public {
        vm.startPrank(a); k.write(TE, "A"); k.write(TE, "A"); vm.stopPrank();
        vm.prank(b); k.write(TE, "B");
        assertEq(k.count(), 3); assertEq(k.writers(), 2);
        assertEq(k.written(a), 2); assertEq(k.written(b), 1);
        assertEq(k.kotisCompleted(), 0);
    }
    function test_events() public {
        vm.expectEmit(true, true, true, true);
        emit EternalRamaKoti.Transfer(address(0), a, 1);
        vm.expectEmit(true, true, true, true);
        emit EternalRamaKoti.Written(a, 1, 0);
        vm.prank(a); k.write(TE, "A");
    }
    function test_nameRules() public {
        bytes memory long = new bytes(32); for (uint256 i; i < 32; i++) long[i] = "a";
        _bad(""); _bad(string(long));
        _bad("a<b"); _bad("a>b"); _bad("a&b"); _bad("a\"b"); _bad("a'b"); _bad("a`b"); _bad("a\\b");
        _bad("a\nb"); _bad(string(abi.encodePacked("a", bytes1(0x7F))));
        _bad("Srini1"); _bad("Srini_S"); _bad("Srini, S"); _bad(unicode"శ్రీనివాస"); _bad(unicode"Sriní");
        vm.prank(a); uint256 id = k.write(TE, "Srinivasa Somepalli");
        (,,, string memory nm,) = k.entry(id);
        assertEq(nm, "Srinivasa Somepalli");
        vm.prank(a); id = k.write(TE, "A. B-C");
        (,,, nm,) = k.entry(id);
        assertEq(nm, "A. B-C");
    }
    function _bad(string memory nm) internal {
        vm.expectRevert(EternalRamaKoti.BadName.selector);
        k.write(TE, nm);
    }
    function test_thirtyOneBytesPasses() public {
        bytes memory n = new bytes(31); for (uint256 i; i < 31; i++) n[i] = "z";
        vm.prank(a); uint256 id = k.write(TE, string(n));
        (,,, string memory nm,) = k.entry(id);
        assertEq(nm, string(n));
    }
    function test_nameIsolation() public {
        // a 1-byte name must not leak calldata bytes that follow it
        vm.prank(a); uint256 id = k.write(TE, "Z");
        (,,, string memory nm,) = k.entry(id);
        assertEq(bytes(nm).length, 1); assertEq(nm, "Z");
    }
    function test_kotiComplete() public {
        vm.store(address(k), bytes32(uint256(0)), bytes32(uint256(9_999_999)));
        vm.expectEmit(true, false, false, true);
        emit EternalRamaKoti.KotiComplete(1);
        vm.prank(a); uint256 id = k.write(TE, "A");
        assertEq(id, 10_000_000); assertEq(k.kotisCompleted(), 1);
        vm.store(address(k), bytes32(uint256(0)), bytes32(uint256(19_999_999)));
        vm.expectEmit(true, false, false, true);
        emit EternalRamaKoti.KotiComplete(2);
        vm.prank(a); k.write(TE, "A");
    }
    function test_ethRejected() public {
        vm.deal(a, 1 ether);
        vm.prank(a);
        (bool ok,) = address(k).call{value: 1}("");
        assertFalse(ok);
        vm.prank(a);
        (ok,) = address(k).call(bytes(TE));
        assertFalse(ok);
    }
    function test_gas() public {
        vm.prank(b); k.write(TE, "Warm");          // contract no longer fresh: count/writers nonzero
        vm.prank(a); k.write(TE, "Srini");
        uint256 first = vm.snapshotGasLastCall("write_first");
        vm.prank(a); k.write(TE, "Srini");
        uint256 repeat = vm.snapshotGasLastCall("write_repeat");
        assertLt(first, 130_000, "first write gas");
        assertLt(repeat, 110_000, "repeat write gas");
    }
}
