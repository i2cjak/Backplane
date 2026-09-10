// Index source identities without interpreting KiCad geometry. The mature parser
// remains responsible for every symbol, pad, layer, and coordinate transform.
function children(source) {
  const nodes = [];
  let depth = 0;
  let start = -1;
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < source.length; index++) {
    const character = source[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') quoted = false;
      continue;
    }
    if (character === '"') quoted = true;
    else if (character === ";") {
      const newline = source.indexOf("\n", index);
      index = newline < 0 ? source.length : newline;
    } else if (character === "(") {
      if (depth === 1) start = index;
      depth++;
    } else if (character === ")") {
      depth--;
      if (depth === 1 && start >= 0) {
        nodes.push(source.slice(start, index + 1));
        start = -1;
      }
    }
  }
  if (depth !== 0 || quoted)
    throw new Error("The saved KiCad file is incomplete. Waiting for a complete save.");
  return nodes;
}

export function indexNativeSources(sources, previous) {
  const items = new Map();
  const signatures = new Map();
  const global = [];
  let serial = previous?.serial ?? 0;
  for (const source of sources) {
    global.push(source.filename);
    for (const raw of children(source.content)) {
      const identity = children(raw).find((node) => /^\((?:uuid|tstamp)\s/.test(node));
      const id = identity?.match(/^\((?:uuid|tstamp)\s+"?([^"\s)]+)/)?.[1];
      if (!id || items.has(id)) {
        global.push(raw);
        continue;
      }
      const version =
        previous?.items.get(id)?.raw === raw ? previous.items.get(id).version : ++serial;
      items.set(id, { raw, version });
      signatures.set(id, String(version));
    }
  }
  const context = global.join("\n");
  const changed = new Set();
  if (previous) {
    for (const [id, item] of items) if (previous.items.get(id)?.raw !== item.raw) changed.add(id);
    for (const id of previous.items.keys()) if (!items.has(id)) changed.add(id);
  }
  return {
    items,
    signatures,
    context,
    changed,
    serial,
    globalChanged: previous?.context !== context,
  };
}
