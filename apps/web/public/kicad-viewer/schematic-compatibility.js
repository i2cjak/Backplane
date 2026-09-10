/*
 * KiCad 10 can omit placed `(pin ...)` records from schematic symbols. The
 * pin definitions still live in lib_symbols, and the mature painter expects
 * placed PinInstance objects for both pin artwork and hit-test bboxes.
 * Hydrate only missing instances; explicit fork-specific pin records remain
 * authoritative.
 */

function pinNumber(definition) {
  const value = definition?.number?.text ?? definition?.number;
  return value === undefined || value === null ? undefined : String(value);
}

function pinUnit(definition) {
  const value = definition?.unit;
  return Number.isFinite(value) ? value : 0;
}

function symbolUnit(symbol) {
  const value = symbol?.unit;
  return Number.isFinite(value) ? value : 0;
}

function libraryPins(libSymbol) {
  const pins = [];
  const visited = new Set();
  const visit = (symbol) => {
    if (!symbol || visited.has(symbol)) return;
    visited.add(symbol);
    for (const pin of symbol.libPins ?? []) pins.push(pin);
    for (const child of symbol.children ?? []) visit(child);
  };
  visit(libSymbol);
  return pins;
}

function pinConstructor(core, symbols) {
  for (const symbol of symbols) {
    for (const pin of symbol?.pins ?? []) {
      if (typeof pin?.constructor === "function" && pin.constructor !== Object)
        return pin.constructor;
    }
  }
  for (const constructor of core?.painter?.painters?.keys?.() ?? []) {
    if (constructor?.name === "PinInstance") return constructor;
  }
  return undefined;
}

function makePin(Constructor, symbol, definition, uuid) {
  const number = pinNumber(definition);
  const input = { number, uuid, alternate: "" };
  try {
    return new Constructor(input, symbol);
  } catch {
    // The mature bundle's PinInstance constructor is stable, but this keeps
    // the adapter compatible with a fork that exposes the same prototype with
    // a changed constructor signature.
    const pin = Object.create(Constructor.prototype);
    pin.parent = symbol;
    pin.highlighted = false;
    pin.number = number;
    pin.uuid = uuid;
    pin.alternate = "";
    return pin;
  }
}

export function hydrateSchematicPinInstances(core) {
  const document = core?.document;
  const symbols = document?.symbols instanceof Map ? [...document.symbols.values()] : [];
  if (!symbols.length) return { hydrated: 0, symbols: 0, skipped: 0 };

  const Constructor = pinConstructor(core, symbols);
  if (!Constructor) return { hydrated: 0, symbols: 0, skipped: symbols.length };

  let hydrated = 0;
  let touchedSymbols = 0;
  let skipped = 0;
  for (const symbol of symbols) {
    // KiCad stores ordinary symbol pins on child unit definitions (for
    // example Device:C_1_1), while the root LibSymbol's libPins is empty.
    // Walk the complete definition tree so this works for both single-unit
    // symbols and the fork's multi-unit/custom library symbols.
    let definitions;
    try {
      definitions = libraryPins(symbol?.lib_symbol);
    } catch {
      definitions = [];
    }
    if (!definitions.length) {
      skipped += 1;
      continue;
    }
    const existing = new Set((symbol.pins ?? []).map((pin) => pinNumber(pin)));
    const unit = symbolUnit(symbol);
    let added = 0;
    for (const definition of definitions) {
      const number = pinNumber(definition);
      if (!number || existing.has(number)) continue;
      const definitionUnit = pinUnit(definition);
      if (unit && definitionUnit && unit !== definitionUnit) continue;
      const uuid = `${symbol.uuid ?? symbol.reference ?? "symbol"}:pin:${number}`;
      (symbol.pins ??= []).push(makePin(Constructor, symbol, definition, uuid));
      existing.add(number);
      hydrated += 1;
      added += 1;
    }
    if (added) touchedSymbols += 1;
  }
  return { hydrated, symbols: touchedSymbols, skipped };
}

export { pinNumber, pinUnit, symbolUnit };
