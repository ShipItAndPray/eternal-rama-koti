// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {Forms} from "../src/Forms.sol";

contract FormsTest is Test {
    function test_matchesGlyphsJson() public view {
        string memory j = vm.readFile("glyphs/forms.json");
        for (uint8 i = 0; i < Forms.COUNT; i++) {
            string memory key = string.concat("[", vm.toString(i), "]");
            assertEq(Forms.form(i), vm.parseJsonString(j, string.concat(key, ".form")));
            assertEq(Forms.language(i), vm.parseJsonString(j, string.concat(key, ".language")));
        }
    }
    function test_distinct() public pure {
        for (uint8 i = 0; i < Forms.COUNT; i++)
            for (uint8 k = i + 1; k < Forms.COUNT; k++)
                assertTrue(keccak256(bytes(Forms.form(i))) != keccak256(bytes(Forms.form(k))));
    }
    function test_badLangReverts() public {
        vm.expectRevert(Forms.BadLang.selector);
        this.callForm(Forms.COUNT);
    }
    function callForm(uint8 i) external pure returns (string memory) { return Forms.form(i); }
}
