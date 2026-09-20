// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";
import {Helpers} from "./Helpers.sol";

contract TokenTest is Test {
    EternalRamaKoti k; address a = address(0xA11CE); address b = address(0xB0B);
    string constant TE = unicode"శ్రీరామ";
    function setUp() public { k = Helpers.deployKoti(); vm.prank(a); k.write(TE, "A"); }

    function test_nameSymbol() public view { assertEq(k.name(), "Eternal Rama Koti"); assertEq(k.symbol(), "RAMA"); }
    function test_ownerBalance() public view { assertEq(k.ownerOf(1), a); assertEq(k.balanceOf(a), 1); assertEq(k.balanceOf(b), 0); }
    function test_ownerOfMissing() public { vm.expectRevert(EternalRamaKoti.NoToken.selector); k.ownerOf(2); vm.expectRevert(EternalRamaKoti.NoToken.selector); k.ownerOf(0); }
    function test_balanceOfZeroReverts() public { vm.expectRevert(EternalRamaKoti.NoToken.selector); k.balanceOf(address(0)); }
    function test_soulbound() public {
        vm.startPrank(a);
        vm.expectRevert(EternalRamaKoti.Soulbound.selector); k.transferFrom(a, b, 1);
        vm.expectRevert(EternalRamaKoti.Soulbound.selector); k.safeTransferFrom(a, b, 1);
        vm.expectRevert(EternalRamaKoti.Soulbound.selector); k.safeTransferFrom(a, b, 1, "");
        vm.expectRevert(EternalRamaKoti.Soulbound.selector); k.approve(b, 1);
        vm.expectRevert(EternalRamaKoti.Soulbound.selector); k.setApprovalForAll(b, true);
        vm.stopPrank();
        assertEq(k.getApproved(1), address(0)); assertFalse(k.isApprovedForAll(a, b)); assertTrue(k.locked(1));
        vm.expectRevert(EternalRamaKoti.NoToken.selector); k.locked(2);
    }
    function test_interfaces() public view {
        assertTrue(k.supportsInterface(0x01ffc9a7)); assertTrue(k.supportsInterface(0x80ac58cd));
        assertTrue(k.supportsInterface(0x5b5e139f)); assertTrue(k.supportsInterface(0xb45a3c0e));
        assertFalse(k.supportsInterface(0xffffffff)); assertFalse(k.supportsInterface(0x12345678));
    }
}
