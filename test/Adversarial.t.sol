// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// Adversarial review tests. Each test documents a probe; see the review report for severity.
import {Test, Vm, stdError} from "forge-std/Test.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";
import {DataStore} from "../src/lib/DataStore.sol";
import {Base64} from "../src/lib/Base64.sol";
import {Helpers} from "./Helpers.sol";

/// Spawns N throwaway contracts in ONE transaction; each writes once from its own address.
contract Factory {
    function spawn(EternalRamaKoti k, uint256 n) external {
        for (uint256 i; i < n; i++) new Child(k);
    }
}
contract Child {
    constructor(EternalRamaKoti k) { k.write(unicode"శ్రీరామ", "Bot"); }
}
/// A minimal "batch executor" the way an EIP-7702 delegated EOA would use one.
contract Twice {
    function twice(EternalRamaKoti k) external { k.write("Ram", "Bot"); k.write("Ram", "Bot"); }
}

contract AdversarialTest is Test {
    EternalRamaKoti k;
    string constant TE = unicode"శ్రీరామ";
    address a = address(0xA11CE);

    function setUp() public { k = Helpers.deployKoti(); }

    // ------------------------------------------------------------ one-tx batching

    function test_factoryCannotWrite() public {
        Factory f = new Factory();
        vm.expectRevert(EternalRamaKoti.OnlyWallets.selector);
        f.spawn(k, 25);                       // children are contracts, never tx.origin
        assertEq(k.count(), 0);
        assertEq(k.writers(), 0);
    }

    function test_eip7702DelegatedEoaCannotWriteTwiceDirectly() public {
        (address alice, uint256 pk) = makeAddrAndKey("alice");
        Twice impl = new Twice();
        Vm.SignedDelegation memory d = vm.signDelegation(address(impl), pk);
        vm.attachDelegation(d);
        assertGt(alice.code.length, 0);
        vm.prank(alice, alice);
        vm.expectRevert(EternalRamaKoti.OnePerBlock.selector);
        Twice(alice).twice(k);                // both writes have msg.sender == alice
        assertEq(k.count(), 0);
    }

    function test_eip7702FactoryCannotWrite() public {
        (address alice, uint256 pk) = makeAddrAndKey("alice");
        Factory impl = new Factory();
        vm.attachDelegation(vm.signDelegation(address(impl), pk));
        vm.prank(alice, alice);
        vm.expectRevert(EternalRamaKoti.OnlyWallets.selector);
        Factory(alice).spawn(k, 10);          // the children, not alice, would be msg.sender
        assertEq(k.count(), 0);
    }

    // ------------------------------------------------------------ name packing

    function _slotName(uint256 id) internal view returns (bytes32) {
        bytes32 base = keccak256(abi.encode(id, uint256(3)));
        return vm.load(address(k), bytes32(uint256(base) + 1));
    }

    /// Hand-crafted calldata: the name's 32-byte word is "Zz" followed by 30 bytes of 0xFF.
    /// Solidity's ABI decoder does not check padding, so calldataload sees the dirty bytes.
    function test_dirtyCalldataTailIsMasked() public {
        bytes memory rama = bytes(TE);
        bytes memory cd = abi.encodePacked(
            EternalRamaKoti.write.selector,
            uint256(0x40), uint256(0x80),
            rama.length, rama, new bytes(32 - rama.length),
            uint256(2), bytes2("Zz"), bytes30(type(uint240).max)
        );
        vm.prank(a, a);
        (bool ok, bytes memory ret) = address(k).call(cd);
        assertTrue(ok);
        uint256 id = abi.decode(ret, (uint256));
        (,,, string memory nm,) = k.entry(id);
        assertEq(nm, "Zz");
        assertEq(_slotName(id), bytes32("Zz"));   // storage word has zero tail
    }

    function test_thirtyOneByteNameWithDirtyByte32() public {
        bytes memory rama = bytes(TE);
        bytes memory z = new bytes(31); for (uint256 i; i < 31; i++) z[i] = "z";
        bytes memory cd = abi.encodePacked(
            EternalRamaKoti.write.selector,
            uint256(0x40), uint256(0x80),
            rama.length, rama, new bytes(32 - rama.length),
            uint256(31), z, bytes1(0xFF)
        );
        vm.prank(a, a);
        (bool ok, bytes memory ret) = address(k).call(cd);
        assertTrue(ok);
        uint256 id = abi.decode(ret, (uint256));
        (,,, string memory nm,) = k.entry(id);
        assertEq(nm, string(z));
        assertEq(uint8(_slotName(id)[31]), 0);
    }

    function test_thirtyTwoByteNameRejected() public {
        bytes memory z = new bytes(32); for (uint256 i; i < 32; i++) z[i] = "z";
        vm.prank(a, a);
        vm.expectRevert(EternalRamaKoti.BadName.selector);
        k.write(TE, string(z));
    }

    // ------------------------------------------------------------ constructor / glyphs

    function test_constructorRejectsDeadGlyphs() public {
        address[6] memory g;                  // all zero: no code anywhere
        vm.expectRevert(EternalRamaKoti.BadGlyph.selector);
        new EternalRamaKoti(g);
    }

    function test_constructorRejectsDelegatedEoaAsGlyph() public {
        (address eoa, uint256 pk) = makeAddrAndKey("glyph-eoa");
        vm.attachDelegation(vm.signDelegation(address(new Twice()), pk));
        address[6] memory g;
        for (uint256 i; i < 6; i++) g[i] = eoa;   // 0xef0100.. delegation designator, first byte is not STOP
        vm.expectRevert(EternalRamaKoti.BadGlyph.selector);
        new EternalRamaKoti(g);
    }
    function test_constructorRejectsRealCodeAsGlyph() public {
        address[6] memory g;
        for (uint256 i; i < 6; i++) g[i] = address(new Twice());   // real bytecode, first byte is not STOP
        vm.expectRevert(EternalRamaKoti.BadGlyph.selector);
        new EternalRamaKoti(g);
    }
    function test_constructorRejectsSwappedGlyphs() public {
        address[6] memory g;
        for (uint8 i; i < 6; i++) g[i] = k.glyphs(i);
        (g[1], g[2]) = (g[2], g[1]);              // valid data contracts, wrong slots
        vm.expectRevert(EternalRamaKoti.BadGlyph.selector);
        new EternalRamaKoti(g);
    }
    function test_glyphGetterMatchesData() public view {
        for (uint8 i; i < 6; i++) {
            bytes memory d = bytes(vm.readFile(string.concat("glyphs/", vm.toString(i), ".txt")));
            assertEq(DataStore.get(k.glyphs(i)), d);
        }
    }

    function test_glyphContractCannotBeCalledIntoDoingAnything() public {
        // first byte is STOP: any call halts immediately with empty return, no state change
        bytes memory d = bytes(vm.readFile("glyphs/0.txt"));
        address p = DataStore.put(d);
        assertEq(uint8(p.code[0]), 0x00);
        (bool ok, bytes memory ret) = p.call(hex"ff");
        assertTrue(ok); assertEq(ret.length, 0);
        assertEq(p.code.length, d.length + 1);  // still there: no SELFDESTRUCT reachable
    }

    // ------------------------------------------------------------ boundaries

    function test_blockZeroFirstWriterWorks() public {
        vm.roll(0);
        vm.prank(a, a);
        assertEq(k.write(TE, "Ab"), 1);      // lastBlock is stored +1, so block 0 is not a sentinel
        vm.expectRevert(EternalRamaKoti.OnePerBlock.selector);
        vm.prank(a, a);
        k.write(TE, "Ab");
    }

    function test_tokenURIGasLargestGlyphLastId() public {
        vm.store(address(k), bytes32(uint256(0)), bytes32(uint256(9_999_999)));
        bytes memory z = new bytes(31); for (uint256 i; i < 31; i++) z[i] = "W";
        vm.prank(a, a); uint256 id = k.write("Sri Rama Jayam", string(z));
        assertEq(id, 10_000_000);
        uint256 g0 = gasleft();
        string memory uri = k.tokenURI(id);
        uint256 used = g0 - gasleft();
        emit log_named_uint("tokenURI gas (lang 4, 31-char name, id 1e7)", used);
        emit log_named_uint("tokenURI bytes", bytes(uri).length);
        assertLt(used, 5_000_000);
    }

    function test_base64LargeInputMatchesCheatcode() public pure {
        bytes memory big = new bytes(20_000);
        for (uint256 i; i < big.length; i++) big[i] = bytes1(uint8(i * 7 + 13));
        assertEq(Base64.encode(big), vm.toBase64(big));
    }

    function test_erc721EdgeIds() public {
        vm.prank(a, a); k.write(TE, "Ab");
        vm.expectRevert(EternalRamaKoti.NoToken.selector); k.getApproved(0);
        vm.expectRevert(EternalRamaKoti.NoToken.selector); k.locked(0);
        vm.expectRevert(EternalRamaKoti.NoToken.selector); k.tokenURI(0);
        vm.expectRevert(EternalRamaKoti.NoToken.selector); k.entry(2);
        // interface ids are what the spec says they are
        assertEq(bytes4(keccak256("locked(uint256)")), bytes4(0xb45a3c0e));
    }

    // ------------------------------------------------------------ JSON validity per form

    function _decode(string memory uri, string memory prefix) internal returns (string memory) {
        bytes memory u = bytes(uri); bytes memory p = bytes(prefix);
        bytes memory b64 = new bytes(u.length - p.length);
        for (uint256 i; i < b64.length; i++) b64[i] = u[i + p.length];
        string[] memory cmd = new string[](3);
        cmd[0] = "python3"; cmd[1] = "-c";
        cmd[2] = string.concat("import base64,sys; sys.stdout.buffer.write(base64.b64decode('", string(b64), "'))");
        return string(vm.ffi(cmd));
    }

    function test_everyFormJsonParsesWithWorstCaseName() public {
        string memory worst = "J.R.R. Tolkien-Smythe Jr. A.B.";  // 30 bytes: every separator rule
        for (uint8 i = 0; i < k.LANG_COUNT(); i++) {
            vm.roll(block.number + 1);
            string memory f = k.forms(i); vm.prank(a, a); uint256 id = k.write(f, worst);
            string memory j = _decode(k.tokenURI(id), "data:application/json;base64,");
            assertEq(vm.parseJsonString(j, ".attributes[2].value"), worst);
            assertEq(vm.parseJsonString(j, ".name"), string.concat(k.forms(i), " #", vm.toString(uint256(id))));
            string memory svg = _decode(vm.parseJsonString(j, ".image"), "data:image/svg+xml;base64,");
            assertTrue(vm.indexOf(svg, string.concat(">", worst, "<")) != type(uint256).max);
        }
    }
}
