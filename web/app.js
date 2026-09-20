import {
  createPublicClient, createWalletClient, custom, http, fallback, parseAbi, formatEther, decodeEventLog,
} from "https://cdn.jsdelivr.net/npm/viem@2/+esm";
import { CHAIN } from "./config.js";
import { FORMS, PATHS } from "./glyphs.js";

const ABI = parseAbi([
  "function count() view returns (uint256)",
  "function writers() view returns (uint256)",
  "function kotisCompleted() view returns (uint256)",
  "function written(address) view returns (uint256)",
  "function write(string rama, string name) returns (uint256)",
  "function tokenURI(uint256) view returns (string)",
  "function entry(uint256) view returns (address writer, uint8 lang, uint40 timestamp, string name, string form)",
  "event Written(address indexed writer, uint256 indexed id, uint8 lang)",
]);
const WRITTEN = ABI.find((x) => x.type === "event" && x.name === "Written");
const KOTI = 10_000_000n;
const GAS_PER_WRITE = 110_000n;

const chain = {
  id: CHAIN.id, name: CHAIN.name, nativeCurrency: CHAIN.nativeCurrency,
  rpcUrls: { default: { http: CHAIN.rpcs } },
  blockExplorers: { default: { name: "Explorer", url: CHAIN.explorer } },
};
const pub = createPublicClient({ chain, transport: fallback(CHAIN.rpcs.map((u) => http(u))) });

const $ = (id) => document.getElementById(id);
const state = { lang: 0, complete: false, name: "", provider: null, account: null, busy: false };
const NAME_RE = /^[A-Za-z .-]{1,31}$/;

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
function glyph(id, h) {
  return `<svg class="glyph" viewBox="0 0 1000 400" height="${h}" aria-hidden="true"><path d="${PATHS[id]}"/></svg>`;
}
function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function ago(ts) {
  const d = Math.max(0, Math.floor(Date.now() / 1000) - Number(ts));
  if (d < 60) return "just now";
  if (d < 3600) return `${Math.floor(d / 60)} min ago`;
  if (d < 86400) return `${Math.floor(d / 3600)} h ago`;
  return `${Math.floor(d / 86400)} d ago`;
}
function short(a) { return a.slice(0, 6) + "…" + a.slice(-4); }
function status(msg, bad = false) { const el = $("status"); el.textContent = msg; el.style.color = bad ? "var(--ink)" : ""; }

// ---------- language picker ----------
const LANGS = [...new Set(FORMS.map((f) => f.language))];
function formsOf(lang) { return FORMS.filter((f) => f.language === lang); }
function renderLangs() {
  const box = $("langs");
  box.innerHTML = LANGS.map((l) => {
    const f = formsOf(l)[0];
    return `<button type="button" class="lang" role="radio" aria-checked="false" data-lang="${esc(l)}" title="${esc(f.form)}">${glyph(f.id, 22)}<small>${esc(l)}</small></button>`;
  }).join("");
  box.querySelectorAll(".lang").forEach((b) => b.addEventListener("click", () => selectLanguage(b.dataset.lang)));
}
function selectLanguage(lang) {
  document.querySelectorAll(".lang").forEach((b) => b.setAttribute("aria-checked", String(b.dataset.lang === lang)));
  const fs = formsOf(lang);
  const row = $("variants");
  if (fs.length > 1) {
    row.hidden = false;
    row.innerHTML = fs.map((f) =>
      `<button type="button" class="variant" role="radio" aria-checked="false" data-id="${f.id}">${glyph(f.id, 18)}<small>${esc(f.tradition)} tradition</small></button>`
    ).join("");
    row.querySelectorAll(".variant").forEach((b) => b.addEventListener("click", () => selectForm(Number(b.dataset.id))));
  } else { row.hidden = true; row.innerHTML = ""; }
  selectForm(fs[0].id);
}
function selectForm(id) {
  state.lang = id;
  document.querySelectorAll(".variant").forEach((b) => b.setAttribute("aria-checked", String(Number(b.dataset.id) === id)));
  $("romhint").textContent = FORMS[id].romanized.map((r) => r.split("|")[0]).join("");
  $("rama").value = "";
  onType();
  $("rama").focus({ preventScroll: true });
}

// ---------- typing the name of Rama ----------
function onType() {
  const f = FORMS[state.lang];
  const raw = $("rama").value;
  const norm = raw.toLowerCase().replace(/\s+/g, "");
  // walk the syllables, allowing alternate spellings like "jeyam|jayam"
  let matched = 0, acc = "", onTrack = true;
  for (const syl of f.romanized) {
    const alts = syl.split("|");
    const hit = alts.find((a) => norm.startsWith(acc + a));
    if (hit) { acc += hit; matched++; continue; }
    const rest = norm.slice(acc.length);
    onTrack = alts.some((a) => a.startsWith(rest));
    break;
  }
  const complete = raw === f.form || (matched === f.romanized.length && norm === acc);
  if (matched === f.romanized.length && norm !== acc) onTrack = false;
  if (!complete && f.form.startsWith(raw) && raw !== "") onTrack = true;
  state.complete = complete;
  const ink = $("ink");
  if (complete) ink.innerHTML = glyph(f.id, 52);
  else ink.textContent = f.parts.slice(0, matched).join("");
  const help = $("typehelp");
  const hint = f.romanized.map((r) => r.split("|")[0]).join("");
  if (raw === "") { help.textContent = ""; help.className = "help"; }
  else if (complete) { help.textContent = "Written. Now add your name."; help.className = "help"; }
  else if (onTrack) { help.textContent = "Keep going."; help.className = "help"; }
  else { help.textContent = `Only the letters of ${hint}, in order.`; help.className = "help bad"; }
  updateOffer();
}
function onName() {
  const v = $("name").value;
  state.name = v;
  const bytes = new TextEncoder().encode(v).length;
  const meta = $("namemeta");
  if (v === "") { meta.textContent = "0 of 31"; meta.className = "help"; }
  else if (!NAME_RE.test(v)) { meta.textContent = "English letters, spaces, periods and hyphens only."; meta.className = "help bad"; }
  else { meta.textContent = `${bytes} of 31`; meta.className = "help"; }
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
  const ok = CHAIN.koti && state.complete && NAME_RE.test(state.name.trim()) && state.account && !state.busy;
  $("offer").disabled = !ok;
}

// ---------- wallet ----------
const providers = [];
window.addEventListener("eip6963:announceProvider", (e) => {
  if (!providers.some((p) => p.info.uuid === e.detail.info.uuid)) providers.push(e.detail);
});
window.dispatchEvent(new Event("eip6963:requestProvider"));

async function ensureChain(p) {
  const hex = "0x" + CHAIN.id.toString(16);
  const cur = await p.request({ method: "eth_chainId" });
  if (String(cur).toLowerCase() === hex) return;
  try {
    await p.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hex }] });
  } catch (e) {
    if (e && (e.code === 4902 || /unrecognized|not added/i.test(e.message || ""))) {
      await p.request({ method: "wallet_addEthereumChain", params: [{
        chainId: hex, chainName: CHAIN.name, nativeCurrency: CHAIN.nativeCurrency, rpcUrls: CHAIN.rpcs, blockExplorerUrls: [CHAIN.explorer],
      }] });
    } else throw e;
  }
}
async function connect() {
  const p = providers[0]?.provider || window.ethereum;
  if (!p) {
    const here = encodeURIComponent(location.host + location.pathname);
    status("No wallet found in this browser. Open this page inside a wallet app, or install one.", true);
    $("connect").outerHTML = `<a class="quiet btn" href="https://metamask.app.link/dapp/${here}">Open in MetaMask</a>`;
    return;
  }
  try {
    const accounts = await p.request({ method: "eth_requestAccounts" });
    await ensureChain(p);
    state.provider = p; state.account = accounts[0];
    $("connect").textContent = short(state.account);
    status("");
    const mine = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "written", args: [state.account] });
    if (mine > 0n) status(`You have written ${indian(mine)} ${mine === 1n ? "name" : "names"} so far.`);
    p.on?.("accountsChanged", (a) => { state.account = a[0] || null; $("connect").textContent = state.account ? short(state.account) : "Open your wallet"; updateOffer(); });
    p.on?.("chainChanged", () => location.reload());
  } catch (e) {
    status(e?.shortMessage || e?.message || "The wallet did not connect.", true);
  }
  updateOffer();
}
$("connect").addEventListener("click", connect);

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
    const rc = await pub.waitForTransactionReceipt({ hash });
    if (rc.status !== "success") throw new Error("The transaction reverted.");
    const ev = rc.logs.map((l) => { try { return decodeEventLog({ abi: ABI, data: l.data, topics: l.topics }); } catch { return null; } })
      .find((d) => d && d.eventName === "Written");
    const id = ev.args.id;
    const uri = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "tokenURI", args: [id] });
    const meta = JSON.parse(atob(uri.split("base64,")[1]));
    const mine = await pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: "written", args: [state.account] });
    const r = $("result");
    r.hidden = false;
    r.innerHTML = `<img src="${meta.image}" alt="${esc(meta.name)}, written by ${esc(name)}">
      <p>Written. Entry ${indian(id)}. You have written ${indian(mine)} ${mine === 1n ? "name" : "names"}.
      <a href="${CHAIN.explorer}/tx/${hash}">See the transaction</a>.</p>`;
    status("");
    $("rama").value = ""; onType();
    prependEntry({ id, lang: f.id, name, timestamp: Math.floor(Date.now() / 1000) }, true);
    await refreshCounts();
  } catch (e) {
    status(e?.shortMessage || e?.message || "Something went wrong.", true);
  } finally {
    state.busy = false; updateOffer();
  }
}
$("offer").addEventListener("click", offer);

// ---------- reading the book ----------
async function refreshCounts() {
  if (!CHAIN.koti) return;
  const [count, writers, kotis] = await Promise.all(
    ["count", "writers", "kotisCompleted"].map((fn) => pub.readContract({ address: CHAIN.koti, abi: ABI, functionName: fn }))
  );
  $("count").textContent = indian(count);
  $("writers").textContent = indian(writers);
  $("koti").textContent = kotis > 0n ? `, koti ${kotis + 1n}` : "";
  const inKoti = count % KOTI;
  $("bar").style.width = `${Number(inKoti * 10000n / KOTI) / 100}%`;
  $("bar").parentElement.setAttribute("aria-valuenow", String(inKoti));
}
function entryRow(e, inkin) {
  return `<li class="${inkin ? "inkin" : ""}">${glyph(e.lang, 20)}<span class="who">${esc(e.name)}</span><span class="idx">${indian(e.id)}, ${ago(e.timestamp)}</span></li>`;
}
function prependEntry(e, inkin) {
  const ol = $("recent");
  ol.querySelector(".empty")?.remove();
  ol.insertAdjacentHTML("afterbegin", entryRow(e, inkin));
  while (ol.children.length > 24) ol.lastElementChild.remove();
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
    const last = logs.slice(-24).reverse();
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
selectLanguage(LANGS[0]);
onName();
if (CHAIN.koti) {
  $("contract-link").href = `${CHAIN.explorer}/address/${CHAIN.koti}`;
  refreshCounts(); loadRecent(); refreshCost();
  setInterval(refreshCounts, 20000);
} else {
  $("count").textContent = "0";
  $("writers").textContent = "0";
  $("cost").textContent = "The book is not open yet. The contract has not been deployed.";
  $("recent").innerHTML = `<li class="empty">The book opens when the contract is deployed.</li>`;
  $("contract-link").removeAttribute("href");
}
