// Pure matching logic for typing a form. No DOM. Tested by typing.test.mjs.
// A form has: form (canonical string), romanized (syllables, each may be "a|b"), parts (script syllables).
export function matchTyping(f, raw) {
  const norm = raw.toLowerCase().replace(/\s+/g, "");
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
  if (!complete && raw !== "" && f.form.startsWith(raw)) onTrack = true;
  const partial = complete ? f.form : f.parts.slice(0, matched).join("");
  return { complete, onTrack, matched, partial };
}
export function hintFor(f) {
  return f.romanized.map((r) => r.split("|")[0]).join("");
}

// Same rule as the contract: English letters with single separators; a space may follow a letter
// or a period; hyphen and period must follow a letter; no leading separator; may end with a letter
// or a period; at least two letters; 1 to 31 bytes.
export function validName(name) {
  if (typeof name !== "string" || name.length === 0 || name.length > 31) return false;
  let prev = 0, letters = 0; // 0 start, 1 letter, 2 space, 3 hyphen, 4 period
  for (const ch of name) {
    if (/[A-Za-z]/.test(ch)) { prev = 1; letters++; }
    else if (ch === " ") { if (prev !== 1 && prev !== 4) return false; prev = 2; }
    else if (ch === "-") { if (prev !== 1) return false; prev = 3; }
    else if (ch === ".") { if (prev !== 1) return false; prev = 4; }
    else return false;
  }
  return (prev === 1 || prev === 4) && letters >= 2;
}
