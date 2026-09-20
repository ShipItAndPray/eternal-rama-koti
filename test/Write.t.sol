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
            vm.roll(block.number + 1);
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
        vm.prank(a); k.write(TE, "Ab");
        vm.roll(block.number + 1);
        vm.prank(a); k.write(TE, "Ab");
        vm.prank(b); k.write(TE, "Bc");
        assertEq(k.count(), 3); assertEq(k.writers(), 2);
        assertEq(k.written(a), 2); assertEq(k.written(b), 1);
        assertFalse(k.complete());
    }
    function test_events() public {
        vm.expectEmit(true, true, true, true);
        emit EternalRamaKoti.Transfer(address(0), a, 1);
        vm.expectEmit(true, true, true, true);
        emit EternalRamaKoti.Written(a, 1, 0);
        vm.prank(a); k.write(TE, "Ab");
    }
    function test_nameRules() public {
        bytes memory long = new bytes(32); for (uint256 i; i < 32; i++) long[i] = "a";
        _bad(""); _bad(string(long)); _bad("A");                       // empty, too long, one letter
        _bad("a<b"); _bad("a>b"); _bad("a&b"); _bad("a\"b"); _bad("a'b"); _bad("a`b"); _bad("a\\b");
        _bad("a\nb"); _bad(string(abi.encodePacked("ab", bytes1(0x7F))));
        _bad("Srini1"); _bad("Srini_S"); _bad("Srini, S"); _bad(unicode"శ్రీనివాస"); _bad(unicode"Sriní");
        _bad(" Srini"); _bad("Srini "); _bad("Srini  S"); _bad("..."); _bad("- - -"); _bad("-Srini"); _bad("Srini-");
        _bad("Srini .S"); _bad("Srini -S"); _bad("Srini- S"); _bad("Srini..S"); _bad(".Srini"); _bad("S.");
        string[8] memory good = ["Srinivasa Somepalli", "A.B-C", "Sri", "Jean-Luc Picard", "J.R.R. Tolkien", "K. Srinivas", "R. K. Narayan", "Srinivasa S."];
        for (uint256 i; i < good.length; i++) {
            vm.roll(block.number + 1);
            vm.prank(a); uint256 id = k.write(TE, good[i]);
            (,,, string memory nm,) = k.entry(id);
            assertEq(nm, good[i]);
        }
    }
    function test_onePerAddressPerBlock() public {
        vm.prank(a); k.write(TE, "Ab");
        vm.expectRevert(EternalRamaKoti.OnePerBlock.selector);
        vm.prank(a); k.write(TE, "Ab");
        vm.prank(b); k.write(TE, "Bc");                 // a different address in the same block is fine
        vm.roll(block.number + 1);
        vm.prank(a); k.write(TE, "Ab");                 // next block is fine
        assertEq(k.written(a), 2); assertEq(k.count(), 3);
    }
    function test_contractCannotBatch() public {
        Batcher bt = new Batcher(k);
        vm.expectRevert(EternalRamaKoti.OnePerBlock.selector);
        bt.twice();
        assertEq(k.count(), 0);
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
        vm.prank(a); uint256 id = k.write(TE, "Zz");
        (,,, string memory nm,) = k.entry(id);
        assertEq(bytes(nm).length, 2); assertEq(nm, "Zz");
    }
    function test_bookClosesAtOneCrore() public {
        vm.store(address(k), bytes32(uint256(0)), bytes32(uint256(9_999_999)));
        vm.expectEmit(false, false, false, true);
        emit EternalRamaKoti.KotiComplete(10_000_000);
        vm.prank(a); uint256 id = k.write(TE, "Ab");
        assertEq(id, 10_000_000); assertTrue(k.complete());
        vm.roll(block.number + 1);
        vm.expectRevert(EternalRamaKoti.BookComplete.selector);
        vm.prank(a); k.write(TE, "Ab");
        assertEq(k.count(), 10_000_000);
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
        vm.roll(block.number + 1);
        vm.prank(a); k.write(TE, "Srini");
        uint256 repeat = vm.snapshotGasLastCall("write_repeat");
        assertLt(first, 130_000, "first write gas");
        assertLt(repeat, 110_000, "repeat write gas");
    }
}

contract Batcher {
    EternalRamaKoti k;
    constructor(EternalRamaKoti k_) { k = k_; }
    function twice() external { k.write(unicode"శ్రీరామ", "Bot"); k.write(unicode"శ్రీరామ", "Bot"); }
}
