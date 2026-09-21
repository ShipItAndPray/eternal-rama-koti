import {
  createPublicClient, createWalletClient, custom, http, fallback, parseAbi, formatEther, decodeEventLog,
} from "./vendor/viem.js";
import { CHAIN } from "./config.js";
import { FORMS, PATHS } from "./glyphs.js";
import { matchTyping, hintFor, validName } from "./typing.js";

const ABI = parseAbi([
  "function count() view returns (uint256)",
  "function writers() view returns (uint256)",
  "function complete() view returns (bool)",
  "function written(address) view returns (uint256)",
  "function write(string rama, string name) returns (uint256)",
  "function tokenURI(uint256) view returns (string)",
  "function entry(uint256) view returns (address writer, uint8 lang, uint40 timestamp, string name, string form)",
  "event Written(address indexed writer, uint256 indexed id, uint8 lang)",
]);
const WRITTEN = ABI.find((x) => x.type === "event" && x.name === "Written");
const KOTI = 10_000_000n;
const GAS_PER_WRITE = 110_000n;
const RECENT = 10; // how many recent entries the page shows

const chain = {
  id: CHAIN.id, name: CHAIN.name, nativeCurrency: CHAIN.nativeCurrency,
  rpcUrls: { default: { http: CHAIN.rpcs } },
  blockExplorers: { default: { name: "Explorer", url: CHAIN.explorer } },
};
const pub = createPublicClient({ chain, transport: fallback(CHAIN.rpcs.map((u) => http(u))) });

const $ = (id) => document.getElementById(id);
const state = { lang: 0, complete: false, name: "", provider: null, account: null, busy: false, full: false, nextIndex: 1n, partial: "" };

// ---------- formatting ----------
function indian(n) {
  let s = n.toString();
  if (s.length <= 3) return s;
  const last = s.slice(-3);
  let rest = s.slice(0, -3);
  const groups = [];
  while (rest.length > 2) { groups.unshift(rest.slice(-2)); rest = rest.slice(0, -2); }
  if (rest) groups.unshift(rest);
  return groups.join(",") + "," + last;
}
// Mirrors Renderer.svg in the contract: same box, colors, positions. While the devotee is still
// typing, the word area shows what they have typed so far; once complete it shows the on-chain outline.
function cardSvg(id, partial, complete, name, idx) {
  const nm = name ? esc(name) : "Your name";
  const nmFill = name ? "#3A2A1A" : "rgba(58,42,26,.35)";
  const word = complete
    ? `<svg x="50" y="200" width="500" height="200" viewBox="0 0 1000 400"><path d="${PATHS[id]}" fill="#9B1C1C"/></svg>`
    : `<text x="300" y="325" text-anchor="middle" font-family="serif" font-size="${partial.length > 8 ? 56 : 84}" fill="#9B1C1C">${esc(partial)}</text>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 800" role="img" aria-label="Your NFT as you write it">
<rect width="600" height="800" fill="#FBF3E4"/>
<rect x="24" y="24" width="552" height="752" fill="none" stroke="#E0891F" stroke-width="4"/>
${word}
<text x="300" y="560" text-anchor="middle" font-family="serif" font-size="34" fill="${nmFill}">${nm}</text>
<text x="300" y="620" text-anchor="middle" font-family="serif" font-size="26" fill="#7A5A3A">#${indian(idx)} of 1,00,00,000</text>
</svg>`;
}
function renderCard() {
  const name = validName(state.name.trim()) ? state.name.trim() : "";
  $("card").innerHTML = cardSvg(state.lang, state.partial || "", state.complete, name, state.nextIndex);
}
function glyph(id, h, tight = false) {
  const f = FORMS[id];
  const vb = tight && f.box ? f.box.join(" ") : "0 0 1000 400";
  return `<svg class="glyph" viewBox="${vb}" height="${h}" aria-hidden="true"><path d="${PATHS[id]}"/></svg>`;
}
function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function ago(ts) {
  const d = Math.max(0, Math.floor(Date.now() / 1000) - Number(ts));
  if (d < 60) return "just now";
  if (d < 3600) return `${Math.floor(d / 60)} min ago`;
  if (d < 86400) return `${Math.floor(d / 3600)} h ago`;
  return `${Math.floor(d / 86400)} d ago`;
}
function short(a) { a = String(a); return a.slice(0, 6) + "…" + a.slice(-4); }
function b64json(uri) { // data:application/json;base64,... → object, UTF-8 safe (atob alone garbles Indic text)
  const b64 = uri.split("base64,")[1];
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}
function nftUrl(id) { return `${CHAIN.blockscout}/token/${CHAIN.koti}/instance/${id}`; }
function status(msg, bad = false) { const el = $("status"); el.textContent = msg; el.style.color = bad ? "var(--ink)" : ""; }

// ---------- language picker ----------
function optionLabel(f) {
  const same = FORMS.filter((x) => x.language === f.language).length > 1;
  return same ? `${f.form} (${f.language}, ${f.tradition} tradition)` : `${f.form} (${f.language})`;
}
function renderLangs() {
  const sel = $("form");
  sel.innerHTML = FORMS.map((f) => `<option value="${f.id}">${esc(optionLabel(f))}</option>`).join("");
  sel.addEventListener("change", () => selectForm(Number(sel.value)));
}
function selectForm(id) {
  state.lang = id;
  const f = FORMS[id];
  $("form").value = String(id);
  $("formhelp").textContent = f.language === "English" ? `The ${f.tradition} form, written in English letters.` : `The ${f.tradition} tradition, in ${f.language} script.`;
  $("romhint").textContent = hintFor(f);
  $("rama").placeholder = hintFor(f);
  $("rama").value = "";
  onType();
  renderCard();
}

// ---------- typing the name of Rama ----------
function onType() {
  const f = FORMS[state.lang];
  const raw = $("rama").value;
  const { complete, onTrack, partial } = matchTyping(f, raw);
  state.complete = complete;
  state.partial = partial;
  renderCard();
  const ink = $("ink");
  if (complete) ink.innerHTML = glyph(f.id, 52);
  else ink.textContent = partial;
  const help = $("typehelp");
  const base = `Type <span id="romhint" class="rom">${hintFor(f)}</span> with your keyboard and the script appears on your card, or type the word itself.`;
  if (raw === "") { help.innerHTML = base; help.className = "help"; }
  else if (complete) { help.textContent = "Written. Now add your name."; help.className = "help ok"; }
  else if (onTrack) { help.textContent = "Keep going."; help.className = "help"; }
  else { help.textContent = `Only the letters of ${hintFor(f)}, in order.`; help.className = "help bad"; }
  updateOffer();
}
function onName() {
  const v = $("name").value;
  state.name = v;
  const bytes = new TextEncoder().encode(v).length;
  const meta = $("namemeta");
  if (v === "") { meta.textContent = "0 of 31"; meta.className = "help"; }
  else if (!validName(v)) { meta.textContent = "English letters only, at least two, with single spaces, periods or hyphens between them."; meta.className = "help bad"; }
  else { meta.textContent = `${bytes} of 31`; meta.className = "help"; }
  renderCard();
  updateOffer();
}
function block(e) { e.preventDefault(); status("Please type it. Pasting is not writing.", true); }
for (const id of ["rama", "name"]) {
  const el = $(id);
  el.addEventListener("paste", block);
  el.addEventListener("drop", block);
}
$("rama").addEventListener("input", onType);
$("name").addEventListener("input", onName);

function updateOffer() {
  const ok = CHAIN.koti && !state.full && state.complete && validName(state.name.trim()) && state.account && !state.busy;
  $("offer").disabled = !ok;
}

// ---------- wallet ----------
// EIP-6963: every installed wallet announces itself; we list them all and let the devotee pick one.
const providers = [];
let walletsRendered = false;
window.addEventListener("eip6963:announceProvider", (e) => {
  if (!providers.some((p) => p.info.uuid === e.detail.info.uuid)) providers.push(e.detail);
  renderWallets();
});
window.dispatchEvent(new Event("eip6963:requestProvider"));
setTimeout(renderWallets, 900); // legacy wallets that only set window.ethereum, or none at all

function renderWallets() {
  const box = $("wallets");
  if (state.account) return;
  const list = providers.slice();
  if (list.length === 0 && window.ethereum) list.push({ info: { uuid: "legacy", name: "Browser wallet", icon: "" }, provider: window.ethereum });
  if (list.length === 0) {
    if (walletsRendered) return;
    const here = encodeURIComponent(location.host + location.pathname);
    box.innerHTML = `<p class="help">No wallet found in this browser. Install one, or open this page inside your wallet app.</p>
      <div class="wallet-row">
        <a class="wallet" href="https://metamask.io/download/">Install MetaMask</a>
        <a class="wallet" href="https://metamask.app.link/dapp/${here}">Open in MetaMask app</a>
      </div>`;
    walletsRendered = true;
    return;
  }
  box.innerHTML = `<p class="help">Choose your wallet.</p><div class="wallet-row">` + list.map((d) =>
    `<button type="button" class="wallet" data-uuid="${esc(d.info.uuid)}">${d.info.icon ? `<img src="${esc(d.info.icon)}" alt="">` : ""}${esc(d.info.name)}</button>`
  ).join("") + `</div>`;
  box.querySelectorAll("button.wallet").forEach((b) => b.addEventListener("click", () => connect(list.find((d) => d.info.uuid === b.dataset.uuid))));
  walletsRendered = true;
}

async function ensureChain(p) {
  const hex = "0x" + CHAIN.id.toString(16);
  const cur = await p.request({ method: "eth_chainId" });
  if (String(cur).toLowerCase() === hex) return;
  status(`Switching your wallet to ${CHAIN.name}. Approve it in the wallet.`);
  try {
    await p.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hex }] });
  } catch (e) {
    if (e && (e.code === 4902 || /unrecognized|not added|Unrecognized chain/i.test(e.message || ""))) {
      await p.request({ method: "wallet_addEthereumChain", params: [{
        chainId: hex, chainName: CHAIN.name, nativeCurrency: CHAIN.nativeCurrency, rpcUrls: CHAIN.rpcs, blockExplorerUrls: [CHAIN.explorer],
      }] });
    } else throw e;
  }
}
function walletError(e) {
  const code = e?.code ?? e?.cause?.code;
  if (code === 4001 || /rejected|denied/i.test(e?.message || "")) return "You closed the wallet prompt. Click your wallet to try again.";
  if (code === -32002) return "Your wallet already has a request open. Open the wallet window and finish it.";
  return e?.shortMessage || e?.message || "The wallet did not connect.";
}
async function connect(detail) {
  const p = detail?.provider;
  if (!p) { renderWallets(); return; }
  status(`Opening ${detail.info.name}. Approve the connection there.`);
  try {
    const accounts = await p.request({ method: "eth_requestAccounts" });
    await ensureChain(p);
    state.provider = p; state.account = accounts[0];
    if (!/^0x[0-9a-fA-F]{40}$/.test(String(state.account))) throw new Error("The wallet returned an invalid address.");
    $("wallets").innerHTML = `<p class="help">Connected to ${esc(detail.info.name)} as <span class="rom">${esc(short(state.account))}</span>. <button type="button" class="linkish" id="switch">Use a different wallet</button></p>`;
    $("switch").addEventListener("click", () => { state.account = null; state.provider = null; walletsRendered = false; renderWallets(); updateOffer(); });
    status("");
    const mine = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "written", args: [state.account] });
    if (mine > 0n) status(`You have written ${indian(mine)} ${mine === 1n ? "name" : "names"} so far.`);
    p.on?.("accountsChanged", (a) => { state.account = a[0] || null; if (!state.account) { walletsRendered = false; renderWallets(); } updateOffer(); });
    p.on?.("chainChanged", () => location.reload());
  } catch (e) {
    status(walletError(e), true);
  }
  updateOffer();
}

// ---------- offering ----------
async function offer() {
  if (state.busy) return;
  state.busy = true; updateOffer();
  const f = FORMS[state.lang];
  const name = state.name.trim();
  try {
    const wallet = createWalletClient({ chain, transport: custom(state.provider) });
    status("Confirm in your wallet.");
    const hash = await wallet.writeContract({ address: CHAIN.koti, abi: ABI, functionName: "write", args: [f.form, name], account: state.account });
    status("Sent. Waiting for Ethereum to confirm.");
    if (!/^0x[0-9a-fA-F]{64}$/.test(String(hash))) throw new Error("The wallet returned an invalid transaction hash.");
    const rc = await pub.waitForTransactionReceipt({ hash });
    if (rc.status !== "success") throw new Error("The transaction reverted.");
    const me = state.account.toLowerCase();
    if (String(rc.from).toLowerCase() !== me) throw new Error("That transaction was not sent by your wallet.");
    const ev = rc.logs
      .filter((l) => String(l.address).toLowerCase() === CHAIN.koti.toLowerCase())
      .map((l) => { try { return decodeEventLog({ abi: ABI, data: l.data, topics: l.topics }); } catch { return null; } })
      .find((d) => d && d.eventName === "Written" && String(d.args.writer).toLowerCase() === me);
    if (!ev) throw new Error("No write from your wallet was found in that transaction.");
    const id = ev.args.id;
    const uri = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "tokenURI", args: [id] });
    const meta = b64json(uri);
    const mine = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "written", args: [state.account] });
    const r = $("result");
    r.hidden = false;
    r.innerHTML = `<img src="${meta.image}" alt="${esc(meta.name)}, written by ${esc(name)}">
      <p>Written. Entry ${indian(id)}. You have written ${indian(mine)} ${mine === 1n ? "name" : "names"}.</p>
      <p><a href="${nftUrl(id)}">See your NFT</a> or <a href="${CHAIN.explorer}/tx/${esc(hash)}">the transaction</a>.
      To see it in MetaMask, open the NFTs tab, choose Import NFT, and enter the contract address with token ID ${id}.</p>`;
    status("");
    $("rama").value = ""; onType();
    prependEntry({ id, lang: f.id, name, timestamp: Math.floor(Date.now() / 1000) }, true);
    await refreshCounts();
  } catch (e) {
    status(walletError(e), true);
  } finally {
    state.busy = false; updateOffer();
  }
}
$("offer").addEventListener("click", offer);

// ---------- reading the book ----------
async function refreshCounts() {
  if (!CHAIN.koti) return;
  const [count, writers] = await Promise.all(
    ["count", "writers"].map((fn) => pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: fn }))
  );
  $("count").textContent = indian(count);
  $("writers").textContent = indian(writers);
  $("writers-word").textContent = writers === 1n ? "person has" : "people have";
  state.nextIndex = count + 1n;
  renderCard();
  state.full = count >= KOTI;
  $("koti").textContent = state.full ? ". The book is complete." : "";
  $("bar").style.width = `${Number(count * 10000n / KOTI) / 100}%`;
  $("bar").parentElement.setAttribute("aria-valuenow", String(count));
  if (state.full) { $("cost").textContent = "One crore names have been written. The book is closed."; }
  updateOffer();
}
function entryRow(e, inkin) {
  return `<li class="${inkin ? "inkin" : ""}">${glyph(e.lang, 18, true)}<span class="who">${esc(e.name)}</span><a class="idx" href="${nftUrl(e.id)}">${indian(e.id)}, ${ago(e.timestamp)}</a></li>`;
}
function prependEntry(e, inkin) {
  const ol = $("recent");
  ol.querySelector(".empty")?.remove();
  ol.insertAdjacentHTML("afterbegin", entryRow(e, inkin));
  while (ol.children.length > RECENT) ol.lastElementChild.remove();
}
async function refreshCost() {
  try {
    const gp = await pub.getGasPrice();
    const eth = Number(formatEther(gp * GAS_PER_WRITE));
    if (CHAIN.testnet) {
      $("cost").textContent = `One name costs about ${eth.toFixed(5)} ${CHAIN.name} test ETH in gas. Test ETH is free.`;
      return;
    }
    let usd = null;
    try {
      const r = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd");
      usd = (await r.json()).ethereum.usd;
    } catch {}
    $("cost").textContent = usd
      ? `One name costs about $${(eth * usd).toFixed(3)} in gas right now, paid by you to Ethereum. Nobody else is paid.`
      : `One name costs about ${eth.toFixed(6)} ETH in gas right now, paid by you to Ethereum.`;
  } catch {
    $("cost").textContent = "Could not read the gas price. The wallet will show the cost before you confirm.";
  }
}
async function loadRecent() {
  if (!CHAIN.koti) return;
  try {
    const latest = await pub.getBlockNumber();
    let from = latest > 40000n ? latest - 40000n : 0n;
    if (from < BigInt(CHAIN.deployBlock)) from = BigInt(CHAIN.deployBlock);
    const logs = await pub.getLogs({ address: CHAIN.koti, event: WRITTEN, fromBlock: from, toBlock: "latest" });
    const last = logs.slice(-RECENT).reverse();
    const ol = $("recent");
    if (last.length === 0) { ol.innerHTML = `<li class="empty">Nothing written yet. The first line is yours.</li>`; return; }
    const entries = await Promise.all(last.map((l) => pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "entry", args: [l.args.id] })));
    ol.innerHTML = entries.map((e, i) => entryRow({ id: last[i].args.id, lang: e[1], name: e[3], timestamp: e[2] }, false)).join("");
  } catch (e) {
    $("recent").innerHTML = `<li class="empty">Could not read recent entries right now.</li>`;
  }
}

// ---------- boot ----------
renderLangs();
selectForm(0);
$("invocation").innerHTML = [0, 1, 2].map((i) => glyph(i, 26, true)).join("");
onName();
if (CHAIN.koti) {
  $("contract-link").href = `${CHAIN.explorer}/address/${CHAIN.koti}`;
  $("collection-link").href = `${CHAIN.blockscout}/token/${CHAIN.koti}`;
  refreshCounts(); loadRecent(); refreshCost();
  setInterval(refreshCounts, 20000);
} else {
  $("count").textContent = "0";
  $("writers").textContent = "0";
  $("cost").textContent = "The book is not open yet. The contract has not been deployed.";
  $("recent").innerHTML = `<li class="empty">The book opens when the contract is deployed.</li>`;
  $("contract-link").removeAttribute("href");
  $("collection-link").removeAttribute("href");
}
