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
