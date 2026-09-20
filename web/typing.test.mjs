import test from "node:test";
import assert from "node:assert/strict";
import { matchTyping, hintFor } from "./typing.js";
import { FORMS } from "./glyphs.js";

const by = (lang, form) => FORMS.find((f) => f.language === lang && (!form || f.form === form));
const te = by("Telugu"), ta = by("Tamil"), hi = by("Hindi"), enTa = by("English", "Sri Rama Jayam");

test("every form completes from its hint", () => {
  for (const f of FORMS) {
    const r = matchTyping(f, hintFor(f));
    assert.equal(r.complete, true, f.form);
    assert.equal(r.partial, f.form);
  }
});
test("every form completes from its own script", () => {
  for (const f of FORMS) assert.equal(matchTyping(f, f.form).complete, true, f.form);
});
test("Tamil accepts both jeyam and jayam, spaces and case ignored", () => {
  assert.equal(matchTyping(ta, "sriramajeyam").complete, true);
  assert.equal(matchTyping(ta, "sriramajayam").complete, true);
  assert.equal(matchTyping(ta, "Sri Rama Jeyam").complete, true);
  assert.equal(matchTyping(ta, "SRI RAMA JAYAM").complete, true);
});
test("progressive reveal by syllable", () => {
  assert.deepEqual(matchTyping(te, "s").partial, "");
  assert.deepEqual(matchTyping(te, "sri").partial, "శ్రీ");
  assert.deepEqual(matchTyping(te, "srir").partial, "శ్రీ");
  assert.deepEqual(matchTyping(te, "srira").partial, "శ్రీరా");
  assert.deepEqual(matchTyping(te, "srirama").partial, "శ్రీరామ");
  assert.equal(matchTyping(ta, "sriramaje").partial, "ஸ்ரீ ராம");
  assert.equal(matchTyping(hi, "ra").partial, "रा");
});
test("partials are on track, wrong letters are not, extra letters are not", () => {
  assert.equal(matchTyping(te, "srir").onTrack, true);
  assert.equal(matchTyping(te, "srix").onTrack, false);
  assert.equal(matchTyping(te, "sriramax").onTrack, false);
  assert.equal(matchTyping(te, "sriramax").complete, false);
  assert.equal(matchTyping(ta, "sriramajeyamm").complete, false);
});
test("another language's word does not complete this form", () => {
  assert.equal(matchTyping(te, "ram").complete, false);
  assert.equal(matchTyping(hi, "srirama").complete, false);
  assert.equal(matchTyping(hi, "srirama").onTrack, false);
  assert.equal(matchTyping(enTa, "Sri Rama").complete, false);
  assert.equal(matchTyping(enTa, "Sri Rama").onTrack, true);
});
test("native partial input is on track", () => {
  assert.equal(matchTyping(te, "శ్రీ").onTrack, true);
  assert.equal(matchTyping(te, "శ్రీరామ").complete, true);
});
