import { describe, expect, it } from "vite-plus/test";

const { hydrateSchematicPinInstances } = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}schematic-compatibility.js`
);

class PinInstance {
  parent: unknown;
  number: string;
  uuid: string;
  alternate: string;
  constructor(input: { number: string; uuid: string; alternate: string }, parent: unknown) {
    this.parent = parent;
    this.number = input.number;
    this.uuid = input.uuid;
    this.alternate = input.alternate;
  }
}

type FakeDefinition = { number: { text: string }; unit: number };
type FakeSymbol = {
  uuid?: string;
  reference?: string;
  unit?: number;
  pins: PinInstance[];
  lib_symbol?: { libPins?: FakeDefinition[]; children?: Array<{ libPins?: FakeDefinition[] }> };
};

function coreFor(symbol: FakeSymbol) {
  const painter = { painters: new Map([[PinInstance, {}]]) };
  return { document: { symbols: new Map([["C11", symbol]]) }, painter };
}

describe("KiCad schematic compatibility", () => {
  it("hydrates omitted KiCad 10 placed pins from library definitions", () => {
    const symbol: FakeSymbol = {
      uuid: "c11-uuid",
      reference: "C11",
      unit: 1,
      pins: [],
      lib_symbol: {
        // The real Device:C root has no direct libPins; its pins are on
        // Device:C_1_1. This mirrors the KiCad 10 fixture shape.
        children: [
          {
            libPins: [
              { number: { text: "1" }, unit: 1 },
              { number: { text: "2" }, unit: 1 },
            ],
          },
        ],
      },
    };
    const result = hydrateSchematicPinInstances(coreFor(symbol));
    expect(result).toEqual({ hydrated: 2, symbols: 1, skipped: 0 });
    expect(symbol.pins).toHaveLength(2);
    expect(symbol.pins.map((pin) => pin.number)).toEqual(["1", "2"]);
    expect(symbol.pins[0]?.parent).toBe(symbol);
    expect(symbol.pins[0]?.uuid).toBe("c11-uuid:pin:1");
    expect(hydrateSchematicPinInstances(coreFor(symbol))).toEqual({
      hydrated: 0,
      symbols: 0,
      skipped: 0,
    });
  });

  it("keeps explicit pins and excludes definitions for other units", () => {
    const explicit = new PinInstance({ number: "1", uuid: "existing", alternate: "" }, null);
    const symbol: FakeSymbol = {
      uuid: "u-uuid",
      reference: "U1",
      unit: 2,
      pins: [explicit],
      lib_symbol: {
        children: [
          {
            libPins: [
              { number: { text: "1" }, unit: 1 },
              { number: { text: "2" }, unit: 2 },
            ],
          },
        ],
      },
    };
    const result = hydrateSchematicPinInstances(coreFor(symbol));
    expect(result.hydrated).toBe(1);
    expect(symbol.pins.map((pin) => pin.number)).toEqual(["1", "2"]);
    expect(symbol.pins[0]).toBe(explicit);
  });

  it("reports an unavailable PinInstance constructor without inventing geometry", () => {
    const symbol: FakeSymbol = {
      uuid: "c-uuid",
      unit: 1,
      pins: [],
      lib_symbol: { children: [{ libPins: [{ number: { text: "1" }, unit: 1 }] }] },
    };
    const result = hydrateSchematicPinInstances({
      document: { symbols: new Map([["C", symbol]]) },
    });
    expect(result).toEqual({ hydrated: 0, symbols: 0, skipped: 1 });
    expect(symbol.pins).toHaveLength(0);
  });
});
