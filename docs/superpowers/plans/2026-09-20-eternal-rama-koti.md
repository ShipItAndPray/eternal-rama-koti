# Eternal Rama Koti Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Sepolia-deployed, ownerless contract where one transaction writes one "Sri Rama" in the devotee's chosen script with their name, mints one fully on-chain soulbound NFT, and advances a shared count toward one crore; plus a static web page to write from.

**Architecture:** One Solidity contract holds all state and renders metadata and SVG itself; ten tiny data contracts hold pre-rendered glyph outlines read with `extcodecopy`. A static page (viem over keyless public RPC) reads the chain and sends `write(rama, name)` through the devotee's injected wallet. No backend.

**Tech Stack:** Foundry (forge 1.8.3), Solidity ^0.8.24, Python 3.14 venv with fontTools + uharfbuzz for glyph outlines, viem ESM from jsDelivr, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-09-20-eternal-rama-koti-design.md`

## Global Constraints

- Solidity `^0.8.24`; no runtime dependencies; vendored MIT `Base64` only.
- `KOTI = 10_000_000`; `MAX_NAME_BYTES = 31`; `LANG_COUNT = 10`; token ids start at 1 and equal the write index.
- Name bytes: each `>= 0x20`, `!= 0x7F`, and not one of `< > & " ' \` `. 1 to 31 bytes.
- Soulbound: every transfer and approval path reverts `Soulbound()`.
- Image: no fonts, no external references, under 10 KB.
- Gas targets: repeat write under 110,000; first write under 130,000.
- Chain for this build: Sepolia (11155111). Mainnet is out of scope.
- Web: static, no build step, GA4 tag `G-NNV3CN8D2N`, keyless RPC only.
- Fonts: Noto Serif per script (SIL OFL) in `tools/fonts/`, not committed; glyph paths in `glyphs/` are committed.

---

## File Structure

```
foundry.toml                      solc, optimizer, fs_permissions, ffi for tests
src/EternalRamaKoti.sol           state, write(), ERC-721 soulbound surface, tokenURI, contractURI
src/Forms.sol                     library: canonical form + language label per id (hardcoded)
src/Renderer.sol                  library: indian grouping, uint→string, SVG, JSON
src/lib/Base64.sol                vendored MIT encoder
src/lib/DataStore.sol             library: deploy raw-bytes data contract, read it back
script/Deploy.s.sol               deploys 10 data contracts from glyphs/*.txt then the main contract
test/Forms.t.sol                  forms hash to ids, near-miss rejects
test/Write.t.sol                  write(), name validation, counters, events, koti complete, gas
test/Token.t.sol                  ERC-721 surface, soulbound reverts, interfaces
test/Metadata.t.sol               tokenURI/contractURI decode via ffi, JSON + SVG assertions
test/DataStore.t.sol              round-trip bytes through a data contract
test/Helpers.sol                  deploys glyph data contracts from glyphs/ for tests
tools/build_glyphs.py             shapes each form, writes glyphs/<id>.txt + glyphs/forms.json + glyphs/preview.html
glyphs/0.txt … glyphs/9.txt       SVG path `d` strings, viewBox 0 0 1000 400, no trailing newline
glyphs/forms.json                 [{id, language, form, romanized:[...]}]
glyphs/preview.html               all ten outlines side by side for the eye check
web/index.html web/style.css web/app.js web/config.js web/glyphs.js
README.md
.github/workflows/ci.yml          forge test on push
.github/workflows/pages.yml       publish web/ to GitHub Pages
```

---

### Task 1: Foundry scaffold and Base64

**Files:**
- Create: `foundry.toml`, `src/lib/Base64.sol`, `test/Base64.t.sol`, `.gitignore`

**Interfaces:**
- Produces: `library Base64 { function encode(bytes memory) internal pure returns (string memory); }`

- [ ] **Step 1: Scaffold**

```bash
cd /Users/somepalli/claude/eternal-rama-koti
export PATH="$HOME/.foundry/bin:$PATH"
forge init --no-git --no-commit --force . 2>&1 | tail -2
rm -rf src/Counter.sol test/Counter.t.sol script/Counter.s.sol lib/forge-std/.git
cat > foundry.toml <<'EOF'
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
ffi = true
fs_permissions = [{ access = "read", path = "./glyphs" }]

[fmt]
line_length = 100
EOF
printf 'out/\ncache/\nbroadcast/\n.env\n.venv/\ntools/fonts/*.ttf\nnode_modules/\n' > .gitignore
```

- [ ] **Step 2: Failing test comparing to the `vm.toBase64` cheatcode**

```solidity
// test/Base64.t.sol
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
```

- [ ] **Step 3: Run, expect compile failure (no library)**

Run: `forge test --match-path test/Base64.t.sol`

- [ ] **Step 4: Vendor the encoder**

```solidity
// src/lib/Base64.sol
// SPDX-License-Identifier: MIT
// Adapted from OpenZeppelin Contracts (utils/Base64.sol), MIT.
pragma solidity ^0.8.24;

library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = TABLE;
        string memory result = new string(4 * ((data.length + 2) / 3));
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            let dataPtr := data
            let endPtr := add(data, mload(data))
            for {} lt(dataPtr, endPtr) {} {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 { mstore8(sub(resultPtr, 1), 0x3d) }
        }
        return result;
    }
}
```

- [ ] **Step 5: Run, expect pass**

Run: `forge test --match-path test/Base64.t.sol -vv` — Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: foundry scaffold, vendored Base64 with cheatcode-verified tests"
```

---

### Task 2: Glyph outlines from fonts

**Files:**
- Create: `tools/build_glyphs.py`, `glyphs/0.txt`…`glyphs/9.txt`, `glyphs/forms.json`, `glyphs/preview.html`

**Interfaces:**
- Produces: each `glyphs/<id>.txt` is an SVG path `d` (integers, absolute commands) fitting viewBox `0 0 1000 400`; `glyphs/forms.json` is `[{"id":0,"language":"Telugu","form":"శ్రీరామ","romanized":["sri","ra","ma"]}, …]`.

- [ ] **Step 1: Write the builder**

```python
# tools/build_glyphs.py
# Shapes each canonical form with HarfBuzz, extracts outlines with fontTools,
# normalizes into a 1000x400 box (y-down), writes glyphs/<id>.txt, forms.json, preview.html.
import json, os, sys
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(ROOT, "glyphs")

FORMS = [
    (0, "Telugu",    "శ్రీరామ",  "NotoSerifTelugu",     ["sri", "ra", "ma"]),
    (1, "Hindi",     "श्रीराम",  "NotoSerifDevanagari", ["sri", "ra", "ma"]),
    (2, "Tamil",     "ஸ்ரீராம",  "NotoSerifTamil",      ["sri", "ra", "ma"]),
    (3, "Kannada",   "ಶ್ರೀರಾಮ",  "NotoSerifKannada",    ["sri", "ra", "ma"]),
    (4, "Malayalam", "ശ്രീരാമ",  "NotoSerifMalayalam",  ["sri", "ra", "ma"]),
    (5, "Bengali",   "শ্রীরাম",  "NotoSerifBengali",    ["sri", "ra", "ma"]),
    (6, "Gujarati",  "શ્રીરામ",  "NotoSerifGujarati",   ["sri", "ra", "ma"]),
    (7, "Odia",      "ଶ୍ରୀରାମ",  "NotoSerifOriya",      ["sri", "ra", "ma"]),
    (8, "Punjabi",   "ਸ਼੍ਰੀਰਾਮ",  "NotoSerifGurmukhi",   ["sri", "ra", "ma"]),
    (9, "English",   "Sri Rama", "NotoSerif",           ["sri", " ra", "ma"]),
]
BOX_W, BOX_H, PAD = 1000, 400, 40

def font_path(family):
    for f in sorted(os.listdir(FONTS)):
        if f.startswith(family) and f.endswith(".ttf") and not f.startswith(family + "Display"):
            # prefer static Regular, else the variable file
            if "Regular" in f or "[" in f:
                return os.path.join(FONTS, f)
    raise SystemExit(f"font for {family} not found in {FONTS}")

def shape(path, text):
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    upem = face.upem
    font.scale = (upem, upem)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf)
    return upem, [(i.codepoint, p.x_advance, p.x_offset, p.y_offset) for i, p in zip(buf.glyph_infos, buf.glyph_positions)]

def outline(ttf_path, text):
    tt = TTFont(ttf_path)
    gs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    upem, run = shape(ttf_path, text)
    rec = RecordingPen()
    x = 0
    for gid, adv, dx, dy in run:
        g = gs[order[gid]]
        g.draw(TransformPen(rec, (1, 0, 0, 1, x + dx, dy)))
        x += adv
    return rec, upem

def normalize(rec):
    b = BoundsPen(None)
    rec.replay(b)
    xmin, ymin, xmax, ymax = b.bounds
    w, h = xmax - xmin, ymax - ymin
    s = min((BOX_W - 2 * PAD) / w, (BOX_H - 2 * PAD) / h)
    tx = (BOX_W - w * s) / 2 - xmin * s
    ty = (BOX_H + h * s) / 2 + ymin * s   # y flip: svg y = ty - font_y * s
    pen = SVGPathPen(None, ntos=lambda v: str(int(round(v))))
    rec.replay(TransformPen(pen, (s, 0, 0, -s, tx, ty)))
    return pen.getCommands()

def main():
    os.makedirs(OUT, exist_ok=True)
    forms_json, previews = [], []
    for id_, lang, form, family, rom in FORMS:
        fp = font_path(family)
        rec, _ = outline(fp, form)
        d = normalize(rec)
        with open(os.path.join(OUT, f"{id_}.txt"), "w", encoding="utf-8") as f:
            f.write(d)  # no trailing newline
        forms_json.append({"id": id_, "language": lang, "form": form, "romanized": rom})
        previews.append(f'<figure><svg viewBox="0 0 {BOX_W} {BOX_H}" width="300"><rect width="{BOX_W}" height="{BOX_H}" fill="#FBF3E4"/><path d="{d}" fill="#9B1C1C"/></svg><figcaption>{id_} {lang} · {form} · {os.path.basename(fp)} · {len(d)} bytes</figcaption></figure>')
        print(f"{id_} {lang:10s} {len(d):6d} bytes  {os.path.basename(fp)}")
    with open(os.path.join(OUT, "forms.json"), "w", encoding="utf-8") as f:
        json.dump(forms_json, f, ensure_ascii=False, indent=2)
    with open(os.path.join(OUT, "preview.html"), "w", encoding="utf-8") as f:
        f.write('<!doctype html><meta charset="utf-8"><title>glyph preview</title><style>body{font-family:serif;background:#fff}figure{display:inline-block;margin:8px;text-align:center}figcaption{font-size:12px}</style><div style="display:flex;flex-wrap:nowrap;overflow-x:auto">' + "".join(previews) + "</div>")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

Run: `./.venv/bin/python tools/build_glyphs.py` — Expected: ten lines, each path between 1,000 and 8,000 bytes.

- [ ] **Step 3: Eye check**

Open `glyphs/preview.html` in the browser (Playwright MCP, shared Chrome), screenshot, and confirm every form reads correctly with proper conjuncts (శ్రీ, श्री, ஸ்ரீ, etc.). Show the owner the screenshot. Fix any wrong string in `FORMS` and rebuild.

- [ ] **Step 4: Commit**

```bash
git add tools/build_glyphs.py glyphs && git commit -m "feat: glyph outlines for ten scripts, normalized to 1000x400"
```

---

### Task 3: Data contracts (raw bytes as code)

**Files:**
- Create: `src/lib/DataStore.sol`, `test/DataStore.t.sol`

**Interfaces:**
- Produces: `library DataStore { function put(bytes memory data) internal returns (address); function get(address p) internal view returns (bytes memory); }`

- [ ] **Step 1: Failing test**

```solidity
// test/DataStore.t.sol
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
```

- [ ] **Step 2: Run, expect failure**

Run: `forge test --match-path test/DataStore.t.sol`

- [ ] **Step 3: Implement**

```solidity
// src/lib/DataStore.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Stores raw bytes as a contract's runtime code (prefixed with STOP) and reads them back.
library DataStore {
    error CreateFailed();

    function put(bytes memory data) internal returns (address p) {
        // initcode: copy everything after the 11-byte header to memory and return it as runtime code
        bytes memory code = abi.encodePacked(hex"600B5981380380925939F3", hex"00", data);
        assembly { p := create(0, add(code, 32), mload(code)) }
        if (p == address(0)) revert CreateFailed();
    }

    function get(address p) internal view returns (bytes memory out) {
        uint256 size;
        assembly { size := extcodesize(p) }
        size -= 1;
        out = new bytes(size);
        assembly { extcodecopy(p, add(out, 32), 1, size) }
    }
}
```

- [ ] **Step 4: Run, expect pass** — `forge test --match-path test/DataStore.t.sol -vv`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: DataStore for on-chain glyph bytes"`

---

### Task 4: Forms library

**Files:**
- Create: `src/Forms.sol`, `test/Forms.t.sol`

**Interfaces:**
- Produces: `library Forms { uint8 constant COUNT = 10; function form(uint8) internal pure returns (string memory); function language(uint8) internal pure returns (string memory); }` — reverts `BadLang()` for id >= 10.

- [ ] **Step 1: Failing test**

```solidity
// test/Forms.t.sol
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
        this.callForm(10);
    }
    function callForm(uint8 i) external pure returns (string memory) { return Forms.form(i); }
}
```

- [ ] **Step 2: Run, expect failure** — `forge test --match-path test/Forms.t.sol`

- [ ] **Step 3: Implement**

```solidity
// src/Forms.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Forms {
    uint8 internal constant COUNT = 10;
    error BadLang();

    function form(uint8 i) internal pure returns (string memory) {
        if (i == 0) return unicode"శ్రీరామ";
        if (i == 1) return unicode"श्रीराम";
        if (i == 2) return unicode"ஸ்ரீராம";
        if (i == 3) return unicode"ಶ್ರೀರಾಮ";
        if (i == 4) return unicode"ശ്രീരാമ";
        if (i == 5) return unicode"শ্রীরাম";
        if (i == 6) return unicode"શ્રીરામ";
        if (i == 7) return unicode"ଶ୍ରୀରାମ";
        if (i == 8) return unicode"ਸ਼੍ਰੀਰਾਮ";
        if (i == 9) return "Sri Rama";
        revert BadLang();
    }

    function language(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Telugu";
        if (i == 1) return "Hindi";
        if (i == 2) return "Tamil";
        if (i == 3) return "Kannada";
        if (i == 4) return "Malayalam";
        if (i == 5) return "Bengali";
        if (i == 6) return "Gujarati";
        if (i == 7) return "Odia";
        if (i == 8) return "Punjabi";
        if (i == 9) return "English";
        revert BadLang();
    }
}
```

- [ ] **Step 4: Run, expect pass.** If `test_matchesGlyphsJson` fails, the Solidity literal and `build_glyphs.py` disagree; fix whichever is wrong so both match the owner-verified form.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: canonical forms and language labels"`

---

### Task 5: Renderer library

**Files:**
- Create: `src/Renderer.sol`, `test/Renderer.t.sol`

**Interfaces:**
- Produces:
  - `function u(uint256) internal pure returns (string memory)` decimal
  - `function indian(uint256) internal pure returns (string memory)` e.g. `12,34,567`
  - `function hexAddr(address) internal pure returns (string memory)` `0x` + 40 lowercase hex
  - `function svg(bytes memory d, string memory name, uint256 id) internal pure returns (string memory)`
  - `function json(string memory form, string memory language, string memory name, address writer, uint256 id, uint40 ts, string memory svgStr) internal pure returns (string memory)` returns the full `data:application/json;base64,` URI

- [ ] **Step 1: Failing tests**

```solidity
// test/Renderer.t.sol
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
    function test_svgShowsKotiAfterFirst() public view {
        bytes memory d = bytes(vm.readFile("glyphs/0.txt"));
        string memory s = Renderer.svg(d, "Srini", 10_000_001);
        assertTrue(vm.indexOf(s, "Koti 2") != type(uint256).max);
    }
}
```

- [ ] **Step 2: Run, expect failure** — `forge test --match-path test/Renderer.t.sol`

- [ ] **Step 3: Implement**

```solidity
// src/Renderer.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Base64} from "./lib/Base64.sol";

library Renderer {
    uint256 internal constant KOTI = 10_000_000;

    function u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v; uint256 n;
        while (t != 0) { n++; t /= 10; }
        bytes memory b = new bytes(n);
        while (v != 0) { b[--n] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }

    /// Indian digit grouping: last group of 3, then groups of 2.
    function indian(uint256 v) internal pure returns (string memory) {
        bytes memory d = bytes(u(v));
        if (d.length <= 3) return string(d);
        uint256 rest = d.length - 3;               // digits before the last three
        uint256 commas = 1 + (rest - 1) / 2;
        bytes memory out = new bytes(d.length + commas);
        uint256 o = out.length; uint256 i = d.length;
        for (uint256 k = 0; k < 3; k++) out[--o] = d[--i];
        while (i > 0) {
            out[--o] = ",";
            out[--o] = d[--i];
            if (i > 0) out[--o] = d[--i];
        }
        return string(out);
    }

    function hexAddr(address a) internal pure returns (string memory) {
        bytes16 hexd = "0123456789abcdef";
        bytes memory s = new bytes(42);
        s[0] = "0"; s[1] = "x";
        uint160 v = uint160(a);
        for (uint256 i = 41; i > 1; i--) { s[i] = hexd[v & 0xf]; v >>= 4; }
        return string(s);
    }

    function svg(bytes memory d, string memory name, uint256 id) internal pure returns (string memory) {
        string memory koti = id > KOTI
            ? string.concat("<text x=\"300\" y=\"672\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"24\" fill=\"#7A5A3A\">Koti ", u((id - 1) / KOTI + 1), "</text>")
            : "";
        return string.concat(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 800\">",
            "<rect width=\"600\" height=\"800\" fill=\"#FBF3E4\"/>",
            "<rect x=\"24\" y=\"24\" width=\"552\" height=\"752\" fill=\"none\" stroke=\"#E0891F\" stroke-width=\"4\"/>",
            "<svg x=\"50\" y=\"200\" width=\"500\" height=\"200\" viewBox=\"0 0 1000 400\"><path d=\"", string(d), "\" fill=\"#9B1C1C\"/></svg>",
            "<text x=\"300\" y=\"560\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"34\" fill=\"#3A2A1A\">", name, "</text>",
            "<text x=\"300\" y=\"620\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"26\" fill=\"#7A5A3A\">#", indian(id), " of 1,00,00,000</text>",
            koti,
            "</svg>"
        );
    }

    function json(
        string memory form, string memory language, string memory name, address writer,
        uint256 id, uint40 ts, string memory svgStr
    ) internal pure returns (string memory) {
        string memory img = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svgStr)));
        string memory j = string.concat(
            "{\"name\":\"", form, " #", indian(id), "\",",
            "\"description\":\"One name of Rama, written by ", name, " on Ethereum. Entry ", indian(id), " of the Eternal Rama Koti.\",",
            "\"image\":\"", img, "\",",
            "\"attributes\":[",
            "{\"trait_type\":\"Language\",\"value\":\"", language, "\"},",
            "{\"trait_type\":\"Written by\",\"value\":\"", name, "\"},",
            "{\"trait_type\":\"Writer\",\"value\":\"", hexAddr(writer), "\"},",
            "{\"trait_type\":\"Index\",\"display_type\":\"number\",\"value\":", u(id), "},",
            "{\"trait_type\":\"Koti\",\"display_type\":\"number\",\"value\":", u((id - 1) / KOTI + 1), "},",
            "{\"trait_type\":\"Timestamp\",\"display_type\":\"date\",\"value\":", u(ts), "}",
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(j)));
    }
}
```

- [ ] **Step 4: Run, expect pass** — `forge test --match-path test/Renderer.t.sol -vv`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: on-chain SVG and JSON renderer"`

---

### Task 6: The contract — write() and counters

**Files:**
- Create: `src/EternalRamaKoti.sol`, `test/Helpers.sol`, `test/Write.t.sol`

**Interfaces:**
- Consumes: `Forms`, `Renderer`, `DataStore`.
- Produces: `contract EternalRamaKoti` with `constructor(address[10] memory glyphs)`, `write(string calldata rama, string calldata name) returns (uint256 id)`, `count()`, `writers()`, `written(address)`, `kotisCompleted()`, `entry(uint256) returns (address writer, uint8 lang, uint40 timestamp, string name, string form)`, `forms(uint8)`, `languages(uint8)`, events `Written(address indexed writer, uint256 indexed id, uint8 lang)`, `KotiComplete(uint256 indexed koti)`, errors `UnknownForm()`, `BadName()`, `NoToken()`, `Soulbound()`, `NotAllowed()`.

- [ ] **Step 1: Test helper that deploys glyphs from disk**

```solidity
// test/Helpers.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Vm} from "forge-std/Vm.sol";
import {DataStore} from "../src/lib/DataStore.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";

library Helpers {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function deployKoti() internal returns (EternalRamaKoti k) {
        address[10] memory g;
        for (uint8 i = 0; i < 10; i++) {
            g[i] = DataStore.put(bytes(vm.readFile(string.concat("glyphs/", vm.toString(i), ".txt"))));
        }
        k = new EternalRamaKoti(g);
    }
}
```

- [ ] **Step 2: Failing tests**

```solidity
// test/Write.t.sol
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
        for (uint8 i = 0; i < 10; i++) {
            vm.prank(a);
            uint256 id = k.write(Forms.form(i), "Srini");
            assertEq(id, i + 1);
            (address w, uint8 lang,, string memory nm, string memory form) = k.entry(id);
            assertEq(w, a); assertEq(lang, i); assertEq(nm, "Srini"); assertEq(form, Forms.form(i));
        }
        assertEq(k.count(), 10);
    }
    function test_nearMissReverts() public {
        vm.expectRevert(EternalRamaKoti.UnknownForm.selector);
        k.write(unicode"శ్రీరామ ", "Srini");          // trailing space
        vm.expectRevert(EternalRamaKoti.UnknownForm.selector);
        k.write("sri rama", "Srini");                  // wrong case
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
        vm.prank(a); k.write(TE, unicode"శ్రీనివాస సోమేపల్లి");     // 30 bytes of Telugu passes... check length first
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
    function test_kotiComplete() public {
        // count lives in slot 0 (first declared state var)
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
    function test_gas_firstAndRepeat() public {
        vm.prank(a); k.write(TE, "Srini");   // warm-up: first write for a
        vm.prank(a); k.write(TE, "Srini");   // repeat, measured by forge snapshot
    }
}
```

Note for `test_nameRules`: the Telugu name literal must be at most 31 bytes; if the compiler reports the literal is longer, shorten it to `unicode"శ్రీనివాస"` (27 bytes).

- [ ] **Step 3: Run, expect failure** — `forge test --match-path test/Write.t.sol`

- [ ] **Step 4: Implement the contract (write path + views; token surface comes in Task 7 but stub `ownerOf` now)**

```solidity
// src/EternalRamaKoti.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Forms} from "./Forms.sol";
import {Renderer} from "./Renderer.sol";
import {DataStore} from "./lib/DataStore.sol";
import {Base64} from "./lib/Base64.sol";

/// Eternal Rama Koti. One transaction writes one name of Rama. No owner. No admin. Forever.
contract EternalRamaKoti {
    uint256 public constant KOTI = 10_000_000;
    uint256 public constant MAX_NAME_BYTES = 31;
    uint8 public constant LANG_COUNT = 10;

    struct Entry { address writer; uint8 lang; uint40 timestamp; uint8 nameLen; bytes32 name; }

    uint256 public count;                              // slot 0
    uint256 public writers;                            // slot 1
    mapping(address => uint256) public written;        // slot 2
    mapping(uint256 => Entry) internal _entries;       // slot 3
    mapping(bytes32 => uint8) internal _langPlusOne;   // slot 4
    address[10] internal _glyphs;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Locked(uint256 tokenId);
    event Written(address indexed writer, uint256 indexed id, uint8 lang);
    event KotiComplete(uint256 indexed koti);

    error UnknownForm();
    error BadName();
    error NoToken();
    error Soulbound();
    error NotAllowed();

    constructor(address[10] memory glyphs) {
        _glyphs = glyphs;
        for (uint8 i = 0; i < LANG_COUNT; i++) _langPlusOne[keccak256(bytes(Forms.form(i)))] = i + 1;
    }

    // ---------------------------------------------------------------- writing

    function write(string calldata rama, string calldata name) external returns (uint256 id) {
        uint8 lp1 = _langPlusOne[keccak256(bytes(rama))];
        if (lp1 == 0) revert UnknownForm();
        (bytes32 packed, uint8 len) = _packName(name);
        id = ++count;
        if (written[msg.sender] == 0) writers++;
        written[msg.sender]++;
        _entries[id] = Entry(msg.sender, lp1 - 1, uint40(block.timestamp), len, packed);
        emit Transfer(address(0), msg.sender, id);
        emit Locked(id);
        emit Written(msg.sender, id, lp1 - 1);
        if (id % KOTI == 0) emit KotiComplete(id / KOTI);
    }

    function _packName(string calldata name) internal pure returns (bytes32 packed, uint8 len) {
        bytes calldata b = bytes(name);
        if (b.length == 0 || b.length > MAX_NAME_BYTES) revert BadName();
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c < 0x20 || c == 0x7F || c == 0x3C || c == 0x3E || c == 0x26 || c == 0x22 || c == 0x27 || c == 0x5C || c == 0x60) revert BadName();
        }
        len = uint8(b.length);
        assembly { packed := calldataload(b.offset) }
        packed &= bytes32(type(uint256).max << (256 - uint256(len) * 8));
    }

    function _name(Entry memory e) internal pure returns (string memory s) {
        bytes memory out = new bytes(e.nameLen);
        bytes32 n = e.name;
        assembly { mstore(add(out, 32), n) }
        return string(out);
    }

    // ------------------------------------------------------------------ views

    function kotisCompleted() external view returns (uint256) { return count / KOTI; }
    function forms(uint8 lang) external pure returns (string memory) { return Forms.form(lang); }
    function languages(uint8 lang) external pure returns (string memory) { return Forms.language(lang); }

    function entry(uint256 id) external view returns (address writer, uint8 lang, uint40 timestamp, string memory name, string memory form) {
        Entry memory e = _get(id);
        return (e.writer, e.lang, e.timestamp, _name(e), Forms.form(e.lang));
    }

    function _get(uint256 id) internal view returns (Entry memory e) {
        if (id == 0 || id > count) revert NoToken();
        e = _entries[id];
    }

    function ownerOf(uint256 id) public view returns (address) { return _get(id).writer; }

    receive() external payable { revert NotAllowed(); }
    fallback() external payable { revert NotAllowed(); }
}
```

- [ ] **Step 5: Run, expect pass** — `forge test --match-path test/Write.t.sol -vv`

- [ ] **Step 6: Snapshot** — `forge snapshot --match-test test_gas_firstAndRepeat` then read `.gas-snapshot`. Record the number; it must be under 130,000 for the whole test (two writes) minus test overhead. If over, investigate before continuing.

- [ ] **Step 7: Commit** — `git add -A && git commit -m "feat: EternalRamaKoti write path, name packing, counters, koti events"`

---

### Task 7: ERC-721 soulbound surface and metadata

**Files:**
- Modify: `src/EternalRamaKoti.sol`
- Create: `test/Token.t.sol`, `test/Metadata.t.sol`

**Interfaces:**
- Produces: `name()`, `symbol()`, `balanceOf(address)`, `tokenURI(uint256)`, `contractURI()`, `transferFrom`, `safeTransferFrom` ×2, `approve`, `setApprovalForAll`, `getApproved`, `isApprovedForAll`, `locked(uint256)`, `supportsInterface(bytes4)`.

- [ ] **Step 1: Failing token tests**

```solidity
// test/Token.t.sol
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
```

- [ ] **Step 2: Failing metadata tests (decode with ffi)**

```solidity
// test/Metadata.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";
import {Helpers} from "./Helpers.sol";

contract MetadataTest is Test {
    EternalRamaKoti k; address a = address(0xA11CE);
    function setUp() public { k = Helpers.deployKoti(); vm.prank(a); k.write(unicode"శ్రీరామ", unicode"శ్రీనివాస"); }

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
        assertEq(vm.parseJsonString(j, ".attributes[1].value"), unicode"శ్రీనివాస");
        assertEq(vm.parseJsonString(j, ".attributes[2].value"), "0x00000000000000000000000000000000000a11ce");
        assertEq(vm.parseJsonUint(j, ".attributes[3].value"), 1);
        assertEq(vm.parseJsonUint(j, ".attributes[4].value"), 1);
        string memory svg = _decode(vm.parseJsonString(j, ".image"), "data:image/svg+xml;base64,");
        assertTrue(vm.indexOf(svg, "<svg xmlns=\"http://www.w3.org/2000/svg\"") == 0);
        assertTrue(vm.indexOf(svg, unicode">శ్రీనివాస<") != type(uint256).max);
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
    function test_everyLanguageRenders() public {
        for (uint8 i = 0; i < 10; i++) { vm.prank(a); uint256 id = k.write(k.forms(i), "N"); k.tokenURI(id); }
    }
}
```

- [ ] **Step 3: Run both, expect failure** — `forge test --match-path 'test/{Token,Metadata}.t.sol'`

- [ ] **Step 4: Add the token surface to the contract** (append inside the contract body)

```solidity
    // ------------------------------------------------------------ ERC-721 (soulbound)

    function name() external pure returns (string memory) { return "Eternal Rama Koti"; }
    function symbol() external pure returns (string memory) { return "RAMA"; }

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert NoToken();
        return written[owner];
    }

    function tokenURI(uint256 id) external view returns (string memory) {
        Entry memory e = _get(id);
        string memory nm = _name(e);
        string memory svg = Renderer.svg(DataStore.get(_glyphs[e.lang]), nm, id);
        return Renderer.json(Forms.form(e.lang), Forms.language(e.lang), nm, e.writer, id, e.timestamp, svg);
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
```

- [ ] **Step 5: Run everything, expect pass** — `forge test -vv`. Then `forge build --sizes` and confirm `EternalRamaKoti` runtime is under 24,576 bytes.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: soulbound ERC-721 surface, on-chain tokenURI and contractURI"`

---

### Task 8: Deploy script and Sepolia deployment

**Files:**
- Create: `script/Deploy.s.sol`, `.env.example`

- [ ] **Step 1: Script**

```solidity
// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {DataStore} from "../src/lib/DataStore.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(pk);
        address[10] memory g;
        for (uint8 i = 0; i < 10; i++) {
            g[i] = DataStore.put(bytes(vm.readFile(string.concat("glyphs/", vm.toString(i), ".txt"))));
            console2.log("glyph", i, g[i]);
        }
        EternalRamaKoti k = new EternalRamaKoti(g);
        vm.stopBroadcast();
        console2.log("EternalRamaKoti", address(k));
    }
}
```

`.env.example`: `DEPLOYER_KEY=0x...` and `SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com`.

- [ ] **Step 2: Dry run on a local Anvil fork of Sepolia**

```bash
anvil --fork-url https://ethereum-sepolia-rpc.publicnode.com --port 8545 &   # background
DEPLOYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d45c1a45f5e \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vv
```
Expected: 11 contracts created, addresses printed. Then `cast call <koti> "count()(uint256)" --rpc-url http://127.0.0.1:8545` → 0. Send one write with `cast send <koti> "write(string,string)" "శ్రీరామ" "Srini" --private-key <anvil key> --rpc-url http://127.0.0.1:8545` and read `tokenURI(1)`, decode, open the SVG in the browser. Kill anvil.

- [ ] **Step 3: Generate the real deployer key**

```bash
cast wallet new   # prints address + private key
printf 'DEPLOYER_KEY=%s\nSEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com\n' '<private key>' > .env
```
Tell the owner the address and ask them to send it 0.05 Sepolia ETH from a faucet or their own test wallet. Wait for balance: `cast balance <addr> --rpc-url $SEPOLIA_RPC`.

- [ ] **Step 4: Deploy and verify**

```bash
set -a; source .env; set +a
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast -vv
forge verify-contract <koti> src/EternalRamaKoti.sol:EternalRamaKoti --chain sepolia --verifier sourcify --constructor-args $(cast abi-encode "constructor(address[10])" "[<g0>,...,<g9>]")
```
Record the address in `README.md` and `web/config.js`. Commit `broadcast/` is gitignored; commit the address in a `deployments.json` at repo root: `{"sepolia":{"chainId":11155111,"koti":"0x…","glyphs":["0x…"],"block":N}}`.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: deploy script; Sepolia deployment recorded"`

---

### Task 9: Web app

**Files:**
- Create: `web/index.html`, `web/style.css`, `web/app.js`, `web/config.js`, `web/glyphs.js`

**Interfaces:**
- Consumes: contract ABI subset: `count()`, `writers()`, `kotisCompleted()`, `written(address)`, `write(string,string)`, `tokenURI(uint256)`, event `Written(address indexed,uint256 indexed,uint8)`.
- `web/config.js` exports `CHAIN` `{ id: 11155111, name: "Sepolia", rpcs: [...], explorer: "https://sepolia.etherscan.io", blockscout: "https://eth-sepolia.blockscout.com", koti: "0x…" }`.
- `web/glyphs.js` exports `FORMS` (contents of `glyphs/forms.json`) and `PATHS` (id → `d`) for instant local preview of the chosen form.

- [ ] **Step 1: Load the frontend-design skill, then build the page**

Structure of `index.html` (all copy final, no lorem):
1. Header: "Eternal Rama Koti" and one line: "One transaction writes one name of Rama on Ethereum. Forever."
2. Counter block: big Indian-grouped count, progress bar to 1,00,00,000, writers count, "Koti N" when past the first.
3. Write card: language picker (10 chips showing each form using `PATHS` inline SVG), the chosen form large, an input with placeholder "type srirama" that reveals script syllables as you type (romanized) or accepts exact native input, a name input with a live "n/31 bytes" counter, a wallet button, a cost line "≈ $0.00 · 0.0 gwei", and the Offer button.
4. Result: after confirmation, the new token's SVG inline, "Written. You have written N.", and a link to the explorer.
5. Recent: last 24 entries as inline SVG cards from Blockscout logs.
6. Footer: contract address with link, "no owner, no admin, no server", link to GitHub, GA4 tag.

Transliteration rule in `app.js`: normalize typed value by lowercasing and stripping spaces; compare against the concatenation of the language's `romanized` syllables (spaces stripped); reveal the form's script syllables for each fully matched romanized syllable. Script syllable boundaries per language are derived by splitting the form into the same number of parts as `romanized` using these fixed tables:

```js
const SCRIPT_PARTS = {
  0: ["శ్రీ","రా","మ"], 1: ["श्री","रा","म"], 2: ["ஸ்ரீ","ரா","ம"], 3: ["ಶ್ರೀ","ರಾ","ಮ"],
  4: ["ശ്രീ","രാ","മ"], 5: ["শ্রী","রা","ম"], 6: ["શ્રી","રા","મ"], 7: ["ଶ୍ରୀ","ରା","ମ"],
  8: ["ਸ਼੍ਰੀ","ਰਾ","ਮ"], 9: ["Sri"," Ra","ma"],
};
```
The Offer button enables only when `new TextEncoder().encode(rendered)` equals the bytes of the canonical form (or the raw input equals it). Paste, drop, and autocomplete are blocked on both inputs.

Name validation mirrors the contract: bytes 1 to 31, each `>= 0x20`, `!= 0x7F`, none of `<>&"'\`\\`.

Wallet: EIP-6963 discovery, pick the first announced provider (offer a chooser if more than one), `wallet_switchEthereumChain` to `CHAIN.id`. Writes via viem `walletClient.writeContract`. Reads via viem `createPublicClient` with `fallback(CHAIN.rpcs.map(http))`.

Cost line: `gasPrice × 110000` in ETH, times ETH/USD from `https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd`; for Sepolia show "test ETH" instead of dollars.

- [ ] **Step 2: Serve locally and test against Sepolia**

`python3 -m http.server 8080 -d web` then drive it with Playwright MCP in the shared Chrome: pick Telugu, type `srirama`, confirm the form fills, type a Telugu name, connect the owner's wallet (owner does this by hand), send, confirm the token renders. Take screenshots for the owner.

- [ ] **Step 3: Commit** — `git add web && git commit -m "feat: static writing page on Sepolia"`

---

### Task 10: README, GitHub repo, Pages, CI

**Files:**
- Create: `README.md`, `.github/workflows/ci.yml`, `.github/workflows/pages.yml`, `LICENSE`

- [ ] **Step 1: README** covering: what it is, live link, Sepolia address and glyph addresses, the ten forms table, how to write by hand from any wallet (`cast send` example and the Etherscan Write tab), gas cost with the date it was measured, why mainnet and why not yet, honest limitations (bots, system fonts for names), how to build (forge test, build_glyphs), licenses (MIT code, OFL glyph outlines with the Noto version).

- [ ] **Step 2: Workflows**

`ci.yml`: on push, `foundry-rs/foundry-toolchain@v1`, `forge test`, `forge build --sizes`.
`pages.yml`: on push to main, `actions/upload-pages-artifact@v3` with `path: web`, `actions/deploy-pages@v4`.

- [ ] **Step 3: Create repo and push**

```bash
gh repo create ShipItAndPray/eternal-rama-koti --public --source . --push --description "One transaction writes one name of Rama on Ethereum. A shared Rama Koti, fully on-chain, no owner."
gh api -X POST repos/ShipItAndPray/eternal-rama-koti/pages -f build_type=workflow
```
Confirm the Pages URL loads and the counter reads from Sepolia. Add the live link to the README and push again.

- [ ] **Step 4: Commit and verify** — CI green, Pages live, README link works.
