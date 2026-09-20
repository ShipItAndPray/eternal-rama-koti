# Eternal Rama Koti — Design

**Date:** 2026-09-20
**Owner:** ShipItAndPray
**Status:** approved in conversation; mainnet deploy gated on explicit go

## 1. What it is

One shared Rama Koti on Ethereum mainnet. A devotee sends a transaction whose data is
exactly the UTF-8 bytes of `శ్రీరామ`. The contract verifies the bytes, adds one to a
global count, and remembers the writer's own count. One crore (1,00,00,000) writes
completes a koti; the count then continues into the next koti forever.

There is exactly one token: the shared book. It is an ERC-721 held by the contract
itself, non-transferable, whose image is generated on-chain and shows the live count.

Nothing can be paused, edited, upgraded, or owned. No backend, no database, no keys
after deploy. A static web page is the writing surface.

## 2. Non-goals

- No per-devotee tokens. No batching. No relayer or gasless path. No proof of humanity.
- No mobile app. No accounts. No analytics beyond the GA4 tag used on every ShipItAndPray site.
- No second mantra. The string is fixed at deploy. Changing it means a new contract.

## 3. Contract: `EternalRamaKoti.sol`

Solidity ^0.8.24, Foundry, single file, no external dependencies at runtime.

### Constants

| Name | Value |
|---|---|
| `NAME` | `unicode"శ్రీరామ"` (21 bytes UTF-8) |
| `NAME_HASH` | `keccak256(bytes(NAME))` |
| `KOTI` | `10_000_000` |
| `TOKEN_ID` | `1` |

### State

| Name | Type | Meaning |
|---|---|---|
| `count` | `uint256` | total names written, all time |
| `written` | `mapping(address => uint256)` | names written by each address |
| `writers` | `uint256` | distinct addresses that have written at least once |

### Writing

Two entry points, both requiring the exact bytes:

- `fallback()` — `msg.data` must equal `bytes(NAME)`. This is the canonical path: the
  transaction's input data is the name and nothing else.
- `write(string calldata name)` — ABI path for Etherscan's Write Contract tab and
  other tooling. `keccak256(bytes(name))` must equal `NAME_HASH`.

Both call an internal `_write()`:

1. `count += 1`
2. if `written[msg.sender] == 0` then `writers += 1`
3. `written[msg.sender] += 1`
4. emit `Written(address indexed writer, uint256 indexed index)` where `index` is the
   new `count`
5. if `count % KOTI == 0` emit `KotiComplete(uint256 indexed koti)` where `koti = count / KOTI`

Any other calldata, any ETH value, and `receive()` revert. Nothing else is callable.

### Views

`count()`, `written(address)`, `writers()`, `kotisCompleted()` = `count / KOTI`,
`NAME()`, `KOTI()`.

### Token (the shared book)

Minimal ERC-721 surface for exactly one token:

- `name()` = "Eternal Rama Koti", `symbol()` = "RAMAKOTI"
- `ownerOf(1)` = `address(this)`; any other id reverts
- `balanceOf(address(this))` = 1, all others 0
- `tokenURI(1)` = `data:application/json;base64,...` with `name`, `description`,
  `image` (SVG data URI), and `attributes` for count, writers, koti number
- `transferFrom`, `safeTransferFrom`, `approve`, `setApprovalForAll` always revert
- `locked(uint256)` (ERC-5192) returns true for id 1
- `supportsInterface` covers ERC-165, ERC-721, ERC-721Metadata, ERC-5192
- `Transfer(address(0), address(this), 1)` emitted in the constructor so indexers see the mint

### Image

The SVG is built in Solidity from the live count. It contains no fonts. The word
`శ్రీరామ` is a single pre-rendered glyph outline (`<path>` in `<defs>`), placed with
`<use>` into a page grid of 108 cells (9 columns × 12 rows). Cells filled is
`count % 108` rounded so the page visibly fills as writing proceeds, then resets.
Below the grid: the count in Indian grouping (e.g. `12,34,567`), `of 1,00,00,000`,
and `koti N` once at least one koti is complete. Palette: cream page, saffron
border, deep red ink. Digits use a generic serif family so the renderer never
needs a font. Target SVG size under 8 KB.

The outline is produced once, offline, from Noto Sans Telugu (SIL OFL) via
fontTools, simplified, and pasted into the contract as a constant. The build
script and the exact font version are committed so the path is reproducible.

### Gas

Target for one write via `fallback`: under 50,000 gas after the first write from
an address, and under 70,000 for an address's first write. `forge snapshot`
committed and checked in CI.

## 4. Web app: `web/`

Static, no build step, hosted on GitHub Pages under ShipItAndPray. One
`index.html`, one `app.js`, one `style.css`. `viem` loaded from jsDelivr as an ES
module. Config (contract address, chain id, RPC list) in `config.js`.

### Reads (no wallet needed)

- `count`, `writers`, `kotisCompleted` via `eth_call` on keyless public RPCs
  (PublicNode primary, Cloudflare and 1rpc fallbacks; all CORS-verified 2026-09-20)
- The book image via `tokenURI(1)`, decoded and rendered inline. The page shows what
  the chain shows.
- Recent writes: last 20 `Written` events via Blockscout's keyless API, with
  truncated addresses and block times. Failure here is non-fatal.
- Live gas price in USD before signing: `eth_gasPrice` × 45,000 × ETH/USD from
  CoinGecko's keyless endpoint. If CoinGecko fails, show gwei only.

### Writing

1. Connect a wallet via EIP-6963 discovery (injected). If the chain is wrong,
   request a switch.
2. Type the name. Input accepts either native Telugu or romanized `srirama`,
   which is transliterated live. Paste, drop, and autofill are blocked. The
   Offer button enables only on an exact match.
3. Offer sends one transaction: `to` = contract, `data` = hex of the UTF-8 bytes,
   `value` = 0. One name per transaction, always.
4. On confirmation: show "Written. You have written N." and clear the input.
   The count refreshes from chain.
5. If a devotee has written before, the page shows their count on connect.

Mobile: works in wallet in-app browsers. A button offers the MetaMask deep link.

### Design

Devotional and dignified: cream, saffron, deep red, generous whitespace, Telugu
typography. Follow the frontend-design skill when building. Clearly show, above
the fold: the book, the count, the per-name cost, and the one-line explanation.

## 5. Deployment

1. `forge test` green, snapshot committed.
2. Deploy to Sepolia with a freshly generated key held only in `.env` (gitignored).
   Owner tries the web app against Sepolia.
3. Confirm the exact `NAME` bytes with the owner. This is irreversible.
4. Mainnet deploy only on the owner's explicit go. Verify on Sourcify and Etherscan.
5. Discard the deployer key. The contract has no privileged functions.
6. Repo: `ShipItAndPray/eternal-rama-koti`, MIT, README with live link, contract
   address, how to write from any wallet by hand, gas cost, and why mainnet.
   GitHub Pages enabled.

## 6. Testing

Foundry tests cover: correct bytes increment count and writer count; wrong bytes,
empty data, ETH value, and `write()` with a wrong string all revert; same address
writing repeatedly increments its own count and `writers` only once; `Written`
indices are sequential; `KotiComplete` fires at exactly 10,000,000 and 20,000,000
(via `vm.store` on the count slot); `tokenURI(1)` decodes to valid JSON whose image
decodes to an SVG containing the current count; `ownerOf(2)` reverts; every
transfer and approval path reverts; `supportsInterface` returns true for the four
ids and false for a random id; gas snapshot for first and repeat writes.

Web app: manual checklist run against Sepolia in a real browser before mainnet.

## 7. Costs and risks, stated honestly

- Deploy ≈ $1 at 0.063 gwei and ETH $2,624 (measured 2026-09-20). Each write ≈
  $0.008 at those prices, paid by the writer. One crore of writes ≈ $80,000
  collectively at today's gas; gas spikes raise it linearly. The page shows the
  live cost before every signature.
- Bots can write at their own expense. The count measures writes, not intent.
- Public RPCs can rate-limit or vanish; the config lists three and the contract
  address is in the README so anyone can read the chain by other means.
- Etherscan verification needs a free API key; Sourcify does not.
