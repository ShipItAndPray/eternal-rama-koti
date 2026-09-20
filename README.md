# Eternal Rama Koti

**One transaction writes one name of Rama on Ethereum. Forever.**

Live page: https://shipitandpray.github.io/eternal-rama-koti/ (Sepolia test network)

A shared Rama Koti. A devotee picks a language, types the name of Rama in that script,
adds their own name, and sends one transaction. The contract checks the typed bytes
against the canonical form, mints one soulbound token to the devotee, and adds one to
a global count. The book holds exactly one crore (1,00,00,000) names. When the count
reaches one crore, the contract refuses further writes and the book is complete.

Every token is fully on-chain: the script, the devotee's name, the writer's address,
the timestamp, and the sequence number live in the contract, and the image is an SVG
the contract draws itself, with no fonts and no external references.

Once written, a name can never be changed or removed. When the book reaches one crore, it
will be printed and taken to the Ram Mandir.

Nothing can be paused, edited, upgraded, or owned. There is no backend. The page is
static and talks to the chain through public RPC and the devotee's own wallet.

## The forms

| Language | Form | Tradition |
|---|---|---|
| Telugu | శ్రీరామ | Rama Koti, Bhadrachalam |
| Tamil | ஸ்ரீ ராம ஜெயம் | Sri Rama Jayam likhita japam |
| Hindi | राम | Ram Naam Lekhan, Ram Naam Bank Varanasi |
| English | Sri Rama | Telugu |
| English | Sri Rama Jayam | Tamil |
| English | Ram | Hindi |

The contract accepts exactly these byte sequences and nothing else.

## Deployments

| Network | Contract | Deployed |
|---|---|---|
| Sepolia | [`0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef`](https://sepolia.etherscan.io/address/0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef) | 2026-09-20, block 11746350 |

Mainnet is a separate decision, not yet made.

## Write from any wallet, by hand

The page is a convenience. The contract is the truth. From Foundry's `cast`:

```bash
cast send 0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef "write(string,string)" "శ్రీరామ" "Your Name" \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com --private-key <key>
```

Or use the explorer's Write Contract tab with `write(rama, writerName)`. The name must be
1 to 31 bytes of English letters, spaces, periods, and hyphens.

Read the book:

```bash
cast call 0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef "count()(uint256)" --rpc-url https://ethereum-sepolia-rpc.publicnode.com
cast call 0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef "tokenURI(uint256)(string)" 1 --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## Gas

Measured with `forge snapshot` on 2026-09-20: a repeat write costs about 87,700 gas and
an address's first write about 109,900 gas. At mainnet's 0.063 gwei and ETH at $2,624
that day, one name would cost about two cents. On Sepolia it costs nothing real.

## Honest limitations

- Anyone can write at their own expense, including bots. The count measures writes, not
  intent.
- The devotee's name is English-only by rule so it renders on every viewer. The Rama
  form is a glyph outline and never depends on fonts.
- Public RPCs can rate-limit. The page lists three per chain. The contract address is
  above so anyone can read the chain by other means.

## Build

```bash
forge test                       # 32 tests, includes an ffi decode of tokenURI
forge build --sizes              # contract is under 10 KB
python3 -m venv .venv && ./.venv/bin/pip install fonttools uharfbuzz
./.venv/bin/python tools/build_glyphs.py   # regenerates glyphs/ and web/glyphs.js
```

Fonts are Noto Serif for each script (SIL Open Font License), fetched from the
google/fonts repository into `tools/fonts/` and not committed. The glyph outlines in
`glyphs/` are derived from them.

## Layout

```
src/EternalRamaKoti.sol   state, write(), soulbound ERC-721 surface, tokenURI
src/Forms.sol             the canonical forms, languages, traditions
src/Renderer.sol          on-chain SVG and JSON
src/lib/DataStore.sol     raw bytes as contract code (glyph storage)
src/lib/Base64.sol        vendored MIT encoder
script/Deploy.s.sol       deploys six glyph contracts, then the book
tools/build_glyphs.py     shapes each form with HarfBuzz, extracts outlines
glyphs/                   the outlines and forms.json
web/                      the static page
```

## License

Code: MIT. Glyph outlines: derived from Noto Serif fonts under the SIL Open Font License 1.1.
