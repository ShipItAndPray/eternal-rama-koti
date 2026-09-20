// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";
import {Helpers} from "./Helpers.sol";

contract MetadataTest is Test {
    EternalRamaKoti k; address a = address(0xA11CE);
    function setUp() public { k = Helpers.deployKoti(); vm.prank(a, a); k.write(unicode"శ్రీరామ", "Srinivasa Somepalli"); }

    function _decode(string memory uri, string memory prefix) internal returns (string memory) {
        bytes memory u = bytes(uri); bytes memory p = bytes(prefix);
        for (uint256 i; i < p.length; i++) assertEq(u[i], p[i], "prefix");
        bytes memory b64 = new bytes(u.length - p.length);
        for (uint256 i; i < b64.length; i++) b64[i] = u[i + p.length];
        string[] memory cmd = new string[](3);
        cmd[0] = "python3"; cmd[1] = "-c";
        cmd[2] = string.concat("import base64,sys; sys.stdout.buffer.write(base64.b64decode('", string(b64), "'))");
        return string(vm.ffi(cmd));
    }
    function test_tokenURI() public {
        string memory j = _decode(k.tokenURI(1), "data:application/json;base64,");
        assertEq(vm.parseJsonString(j, ".name"), unicode"శ్రీరామ #1");
        assertEq(vm.parseJsonString(j, ".attributes[0].value"), "Telugu");
        assertEq(vm.parseJsonString(j, ".attributes[1].value"), "Telugu");
        assertEq(vm.parseJsonString(j, ".attributes[2].value"), "Srinivasa Somepalli");
        assertEq(vm.parseJsonString(j, ".attributes[3].value"), "0x00000000000000000000000000000000000a11ce");
        assertEq(vm.parseJsonUint(j, ".attributes[4].value"), 1);
        assertEq(vm.parseJsonString(j, ".attributes[5].trait_type"), "Timestamp");
        string memory svg = _decode(vm.parseJsonString(j, ".image"), "data:image/svg+xml;base64,");
        assertTrue(vm.indexOf(svg, "<svg xmlns=\"http://www.w3.org/2000/svg\"") == 0);
        assertTrue(vm.indexOf(svg, ">Srinivasa Somepalli<") != type(uint256).max);
        assertTrue(vm.indexOf(svg, "#1 of 1,00,00,000") != type(uint256).max);
        assertTrue(vm.indexOf(svg, "href") == type(uint256).max, "no external refs");
        assertTrue(vm.indexOf(svg, "font-face") == type(uint256).max, "no fonts");
        assertTrue(bytes(svg).length < 10_000);
    }
    function test_tokenURIMissingReverts() public { vm.expectRevert(EternalRamaKoti.NoToken.selector); k.tokenURI(2); }
    function test_contractURI() public {
        string memory j = _decode(k.contractURI(), "data:application/json;base64,");
        assertEq(vm.parseJsonString(j, ".name"), "Eternal Rama Koti");
        assertTrue(bytes(vm.parseJsonString(j, ".image")).length > 30);
    }
    function test_englishFormCarriesTradition() public {
        vm.roll(block.number + 1); vm.prank(a, a); uint256 id = k.write("Sri Rama Jayam", "Meena");
        string memory j = _decode(k.tokenURI(id), "data:application/json;base64,");
        assertEq(vm.parseJsonString(j, ".name"), "Sri Rama Jayam #2");
        assertEq(vm.parseJsonString(j, ".attributes[0].value"), "English");
        assertEq(vm.parseJsonString(j, ".attributes[1].value"), "Tamil");
    }
    function test_everyLanguageRenders() public {
        for (uint8 i = 0; i < k.LANG_COUNT(); i++) { string memory f = k.forms(i); vm.roll(block.number + 1); vm.prank(a, a); uint256 id = k.write(f, "Nn"); k.tokenURI(id); }
    }
}
