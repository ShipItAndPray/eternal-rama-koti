// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {Renderer} from "../src/Renderer.sol";

contract RendererTest is Test {
    function test_indian() public pure {
        assertEq(Renderer.indian(0), "0");
        assertEq(Renderer.indian(999), "999");
        assertEq(Renderer.indian(1000), "1,000");
        assertEq(Renderer.indian(12345), "12,345");
        assertEq(Renderer.indian(1234567), "12,34,567");
        assertEq(Renderer.indian(10_000_000), "1,00,00,000");
        assertEq(Renderer.indian(123456789012), "1,23,45,67,89,012");
    }
    function test_hexAddr() public pure {
        assertEq(Renderer.hexAddr(address(0xdead)), "0x000000000000000000000000000000000000dead");
    }
    function test_svgContainsParts() public view {
        bytes memory d = bytes(vm.readFile("glyphs/0.txt"));
        string memory s = Renderer.svg(d, "Srini", 12345);
        assertTrue(vm.indexOf(s, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 800\">") == 0);
        assertTrue(vm.indexOf(s, ">Srini<") != type(uint256).max);
        assertTrue(vm.indexOf(s, "#12,345 of 1,00,00,000") != type(uint256).max);
        assertTrue(vm.indexOf(s, "Koti") == type(uint256).max);
        assertTrue(bytes(s).length < 10_000);
    }
}
