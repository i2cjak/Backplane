// The hub's binary frames (core/cbor.bend's wire format) decoded in plain
// JavaScript, straight into Bend's Json tree ({$: "Obj", fields: Field
// chain}, ...), as Cbor.decode reads them. Bend's own decoder walks a list
// cell per byte and was most of a page load on a long log; the phones'
// bridge and the web page both use this one. keys and words are the
// dictionaries (Cbor.keys(), Cbor.words()), read from Bend so they never drift.

// UTF-8 bytes [i, end) as a string
export function utf8(b, i, end) {
  let s = "";
  const cs = [];
  while (i < end) {
    let c = b[i++];
    if (c >= 0xf0) c = ((c & 7) << 18) | ((b[i++] & 63) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
    else if (c >= 0xe0) c = ((c & 15) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
    else if (c >= 0xc0) c = ((c & 31) << 6) | (b[i++] & 63);
    if (c > 0xffff) {
      c -= 0x10000;
      cs.push(0xd800 | (c >> 10), 0xdc00 | (c & 1023));
    } else cs.push(c);
    if (cs.length > 4096) {
      s += String.fromCharCode.apply(null, cs);
      cs.length = 0;
    }
  }
  return s + String.fromCharCode.apply(null, cs);
}

// CBOR bytes to Bend's Json tree, as Cbor.decode reads them; malformed or
// truncated bytes are Null, as there
export function cbor(b, KEYS, WORDS) {
  let i = 0;
  const bad = () => {
    throw new Error("cbor");
  };
  const arg = (ai) => {
    if (ai < 24) return ai;
    if (ai === 24) return b[i++];
    if (ai === 25) return (b[i++] << 8) | b[i++];
    if (ai === 26) return ((b[i++] << 24) | (b[i++] << 16) | (b[i++] << 8) | b[i++]) >>> 0;
    return bad();
  };
  const text = (n) => {
    if (i + n > b.length) bad();
    const s = utf8(b, i, i + n);
    i += n;
    return s;
  };
  // tag: 0 none, 6 a dictionary word, 7 a number's raw text
  const item = (tag) => {
    if (i >= b.length) bad();
    const h = b[i++], maj = h >> 5, ai = h & 31;
    if (maj === 6) return tag === 0 && (ai === 6 || ai === 7) ? item(ai) : bad();
    if (maj === 7) {
      if (tag !== 0) bad();
      if (ai === 20) return { $: "Flag", value: false };
      if (ai === 21) return { $: "Flag", value: true };
      if (ai === 22) return { $: "Null" };
      return bad();
    }
    const n = arg(ai);
    if (i > b.length) bad();
    if (maj === 0 && tag === 0) return { $: "Num", raw: String(n) };
    if (maj === 0 && tag === 6) return n < WORDS.length ? { $: "Str", text: WORDS[n] } : bad();
    if (maj === 1 && tag === 0) return { $: "Num", raw: String(-1 - n) };
    if (maj === 3 && tag === 0) return { $: "Str", text: text(n) };
    if (maj === 3 && tag === 7) return { $: "Num", raw: text(n) };
    if (maj === 4 && tag === 0) {
      const vs = [];
      for (let k = 0; k < n; k += 1) vs.push(item(0));
      let items = { $: "End" };
      for (let k = n - 1; k >= 0; k -= 1) items = { $: "Item", head: vs[k], tail: items };
      return { $: "Arr", items };
    }
    if (maj === 5 && tag === 0) {
      const ks = [], vs = [];
      for (let k = 0; k < n; k += 1) {
        const key = item(0);
        if (key.$ === "Str") ks.push(key.text);
        else if (key.$ === "Num" && /^[0-9]+$/.test(key.raw) && Number(key.raw) < KEYS.length) ks.push(KEYS[Number(key.raw)]);
        else bad();
        vs.push(item(0));
      }
      let fields = { $: "End" };
      for (let k = n - 1; k >= 0; k -= 1) fields = { $: "Field", key: ks[k], value: vs[k], tail: fields };
      return { $: "Obj", fields };
    }
    return bad();
  };
  try {
    const v = item(0);
    return i === b.length ? v : { $: "Null" };
  } catch {
    return { $: "Null" };
  }
}

// a Bend Json tree as plain JavaScript (objects, arrays, strings, numbers,
// booleans, null), as JSON.parse would give its text: no recursion along a
// chain, only per level of nesting
export function plain(j) {
  switch (j.$) {
    case "Null": return null;
    case "Flag": return j.value;
    case "Num": return Number(j.raw);
    case "Str": return j.text;
    case "Arr": {
      const out = [];
      for (let c = j.items; c.$ === "Item"; c = c.tail) out.push(plain(c.head));
      return out;
    }
    case "Obj": {
      const out = {};
      for (let c = j.fields; c.$ === "Field"; c = c.tail) out[c.key] = plain(c.value);
      return out;
    }
    default: return null;
  }
}
