// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Forms} from "./Forms.sol";
import {Renderer} from "./Renderer.sol";
import {DataStore} from "./lib/DataStore.sol";
import {GlyphHashes} from "./GlyphHashes.sol";
import {Base64} from "./lib/Base64.sol";

/// Eternal Rama Koti. One transaction writes one name of Rama. The book holds exactly one crore.
/// No owner. No admin. Forever.
contract EternalRamaKoti {
    uint256 public constant KOTI = 10_000_000;
    uint256 public constant MAX_NAME_BYTES = 31; // English letters, space, period, hyphen only
    uint8 public constant LANG_COUNT = 6; // must equal Forms.COUNT; checked in the constructor

    struct Entry { address writer; uint8 lang; uint40 timestamp; uint8 nameLen; bytes32 name; }

    struct Writer { uint128 count; uint64 lastBlock; }

    uint256 public count;                              // slot 0
    uint256 public writers;                            // slot 1
    mapping(address => Writer) internal _writers;      // slot 2
    mapping(uint256 => Entry) internal _entries;       // slot 3
    mapping(bytes32 => uint8) internal _langPlusOne;   // slot 4
    address[6] internal _glyphs;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Locked(uint256 tokenId);
    event Written(address indexed writer, uint256 indexed id, uint8 lang);
    event KotiComplete(uint256 count);

    error UnknownForm();
    error BadName();
    error NoToken();
    error Soulbound();
    error NotAllowed();
    error BookComplete();
    error OnePerBlock();
    error OnlyWallets();
    error BadGlyph();

    constructor(address[6] memory glyphs) {
        assert(LANG_COUNT == Forms.COUNT);
        for (uint8 i = 0; i < 6; i++) {
            address g = glyphs[i];
            uint256 size;
            assembly { size := extcodesize(g) }
            if (size < 2) revert BadGlyph();
            bytes memory first = new bytes(1);
            assembly { extcodecopy(g, add(first, 32), 0, 1) }
            if (first[0] != 0x00) revert BadGlyph(); // must be a STOP-prefixed data contract, not a delegation or code
            if (keccak256(DataStore.get(g)) != GlyphHashes.hash(i)) revert BadGlyph(); // and hold exactly the committed outline
        }
        _glyphs = glyphs;
        for (uint8 i = 0; i < LANG_COUNT; i++) _langPlusOne[keccak256(bytes(Forms.form(i)))] = i + 1;
    }

    // ---------------------------------------------------------------- writing

    function write(string calldata rama, string calldata writerName) external returns (uint256 id) {
        if (count >= KOTI) revert BookComplete();
        if (msg.sender != tx.origin) revert OnlyWallets(); // a wallet address writes, never a contract: one tx, one name
        uint8 lp1 = _langPlusOne[keccak256(bytes(rama))];
        if (lp1 == 0) revert UnknownForm();
        (bytes32 packed, uint8 len) = _packName(writerName);
        Writer storage w = _writers[msg.sender];
        if (w.lastBlock == block.number + 1) revert OnePerBlock(); // one name per address per block (stored +1 so block 0 is not a sentinel)
        id = ++count;
        if (w.count == 0) writers++;
        w.count += 1;
        w.lastBlock = uint64(block.number + 1);
        _entries[id] = Entry(msg.sender, lp1 - 1, uint40(block.timestamp), len, packed);
        emit Transfer(address(0), msg.sender, id);
        emit Locked(id);
        emit Written(msg.sender, id, lp1 - 1);
        if (id == KOTI) emit KotiComplete(id);
    }

    /// English letters with single separators. A space may follow a letter or a period, so
    /// initials work ("K. Srinivas", "J.R.R. Tolkien"). A hyphen or period must follow a letter.
    /// No leading separator; may end with a letter or a period. At least two letters. 1 to 31 bytes.
    /// The character set is safe to embed in JSON and SVG without escaping.
    function _packName(string calldata writerName) internal pure returns (bytes32 packed, uint8 len) {
        bytes calldata b = bytes(writerName);
        if (b.length == 0 || b.length > MAX_NAME_BYTES) revert BadName();
        uint8 prev = 0; // 0 start, 1 letter, 2 space, 3 hyphen, 4 period
        uint256 letters = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) { prev = 1; letters++; }
            else if (c == 0x20) { if (prev != 1 && prev != 4) revert BadName(); prev = 2; }
            else if (c == 0x2D) { if (prev != 1) revert BadName(); prev = 3; }
            else if (c == 0x2E) { if (prev != 1) revert BadName(); prev = 4; }
            else revert BadName();
        }
        if ((prev != 1 && prev != 4) || letters < 2) revert BadName();
        len = uint8(b.length);
        assembly { packed := calldataload(b.offset) }
        packed &= bytes32(type(uint256).max << (256 - uint256(len) * 8));
    }

    function _name(Entry memory e) internal pure returns (string memory) {
        bytes memory out = new bytes(e.nameLen);
        bytes32 n = e.name;
        assembly { mstore(add(out, 32), n) }
        return string(out);
    }

    // ------------------------------------------------------------------ views

    /// True once the book holds one crore names. No more writes are accepted after that.
    function complete() external view returns (bool) { return count >= KOTI; }
    /// How many names this address has written.
    function written(address a) public view returns (uint256) { return _writers[a].count; }
    /// The data contract holding the glyph outline for a form.
    function glyphs(uint8 lang) external view returns (address) { return _glyphs[lang]; }
    function forms(uint8 lang) external pure returns (string memory) { return Forms.form(lang); }
    function languages(uint8 lang) external pure returns (string memory) { return Forms.language(lang); }
    function traditions(uint8 lang) external pure returns (string memory) { return Forms.tradition(lang); }

    function entry(uint256 id) external view returns (address writer, uint8 lang, uint40 timestamp, string memory writerName, string memory form) {
        Entry memory e = _get(id);
        return (e.writer, e.lang, e.timestamp, _name(e), Forms.form(e.lang));
    }

    function _get(uint256 id) internal view returns (Entry memory e) {
        if (id == 0 || id > count) revert NoToken();
        e = _entries[id];
    }

    function ownerOf(uint256 id) public view returns (address) { return _get(id).writer; }


    // ------------------------------------------------------------ ERC-721 (soulbound)

    function name() external pure returns (string memory) { return "Eternal Rama Koti"; }
    function symbol() external pure returns (string memory) { return "RAMA"; }

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert NoToken();
        return _writers[owner].count;
    }

    function tokenURI(uint256 id) external view returns (string memory) {
        Entry memory e = _get(id);
        string memory nm = _name(e);
        string memory svg = Renderer.svg(DataStore.get(_glyphs[e.lang]), nm, id);
        return Renderer.json(Forms.form(e.lang), Forms.language(e.lang), Forms.tradition(e.lang), nm, e.writer, id, e.timestamp, svg);
    }

    function contractURI() external view returns (string memory) {
        string memory svg = string.concat(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 600\"><rect width=\"600\" height=\"600\" fill=\"#FBF3E4\"/>",
            "<svg x=\"50\" y=\"200\" width=\"500\" height=\"200\" viewBox=\"0 0 1000 400\"><path d=\"", string(DataStore.get(_glyphs[0])), "\" fill=\"#9B1C1C\"/></svg></svg>"
        );
        string memory j = string.concat(
            "{\"name\":\"Eternal Rama Koti\",\"description\":\"A shared Rama Koti on Ethereum. One transaction writes one name of Rama. ",
            Renderer.indian(count), " written so far.\",\"image\":\"data:image/svg+xml;base64,", Base64.encode(bytes(svg)), "\"}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(j)));
    }

    function transferFrom(address, address, uint256) external pure { revert Soulbound(); }
    function safeTransferFrom(address, address, uint256) external pure { revert Soulbound(); }
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure { revert Soulbound(); }
    function approve(address, uint256) external pure { revert Soulbound(); }
    function setApprovalForAll(address, bool) external pure { revert Soulbound(); }
    function getApproved(uint256 id) external view returns (address) { _get(id); return address(0); }
    function isApprovedForAll(address, address) external pure returns (bool) { return false; }
    function locked(uint256 id) external view returns (bool) { _get(id); return true; }

    function supportsInterface(bytes4 i) external pure returns (bool) {
        return i == 0x01ffc9a7 || i == 0x80ac58cd || i == 0x5b5e139f || i == 0xb45a3c0e;
    }

    fallback() external { revert NotAllowed(); } // no receive(): plain ETH transfers revert too
}
