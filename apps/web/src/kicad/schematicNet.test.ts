import { expect, it } from "vite-plus/test";

const { collectSchematicNet, pinAnchor } = await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}schematic-net.js`
);

const point = (x: number, y: number) => ({ x, y });
const wire = (...points: Array<[number, number]>) => ({
  typeId: "Wire",
  pts: points.map(([x, y]) => point(x, y)),
});
const label = (text: string, x: number, y: number) => ({
  typeId: "NetLabel",
  text,
  at: { position: point(x, y) },
});
const schematic = (...items: Array<Record<string, unknown>>) => ({ items: () => items });

it("joins disconnected branches by same-name labels", () => {
  const first = wire([0, 0], [1, 0]);
  const second = wire([5, 0], [6, 0]);
  const firstLabel = label("SDA", 0, 0);
  const secondLabel = label("SDA", 5, 0);
  const result = collectSchematicNet(schematic(first, second, firstLabel, secondLabel), {
    value: "SDA",
  });

  expect(result.netName).toBe("SDA");
  expect(result.items).toEqual(new Set([first, second, firstLabel, secondLabel]));
});

it("joins endpoint T branches but leaves an interior crossing separate", () => {
  const main = wire([0, 0], [10, 0]);
  const branch = wire([5, 0], [5, 4]);
  const crossing = wire([7, -2], [7, 2]);
  const net = label("NET_A", 0, 0);
  const crossingLabel = label("NET_B", 7, -2);
  const result = collectSchematicNet(schematic(main, branch, crossing, net, crossingLabel), {
    value: "NET_A",
  });

  expect(result.items).toContain(main);
  expect(result.items).toContain(branch);
  expect(result.items).not.toContain(crossing);
  expect(result.items).not.toContain(crossingLabel);
});

it("connects a selected pin using its transformed electrical definition anchor", () => {
  const pin = {
    uuid: "pin-1",
    definition: { at: { position: point(1, 0) } },
    parent: {
      get_symbol_transform: () => ({
        transform: (position: { x: number; y: number }) => point(position.x + 10, position.y + 20),
      }),
    },
  };
  const branch = wire([11, 20], [12, 20]);
  const result = collectSchematicNet(schematic(pin, branch), { uuid: "pin-1" });

  expect(pinAnchor(pin)).toEqual(point(11, 20));
  expect(result.items).toContain(pin);
  expect(result.items).toContain(branch);
});

it("uses a junction to connect crossing interiors", () => {
  const horizontal = wire([0, 0], [10, 0]);
  const vertical = wire([5, -2], [5, 2]);
  const junction = { typeId: "Junction", at: { position: point(5, 0) } };
  const net = label("CLK", 0, 0);
  const result = collectSchematicNet(schematic(horizontal, vertical, junction, net), {
    value: "CLK",
  });

  expect(result.items).toContain(vertical);
  expect(result.items).toContain(junction);
});

it("treats a power symbol as a named label attached through its pin", () => {
  const powerPin = {
    uuid: "gnd-pin",
    definition: { at: { position: point(0, 0) } },
    parent: null as null | Record<string, unknown>,
  };
  const power = {
    typeId: "SchematicSymbol",
    value: "GND",
    lib_symbol: { power: true, library_item_name: "GND" },
    unit_pins: [powerPin],
  };
  powerPin.parent = power;
  const branch = wire([0, 0], [0, 2]);
  const result = collectSchematicNet(schematic(power, branch), { value: "GND" });

  expect(result.netName).toBe("GND");
  expect(result.items).toContain(power);
  expect(result.items).toContain(powerPin);
  expect(result.items).toContain(branch);
});

it("does not merge PWR_FLAG markers by their ERC value", () => {
  const firstPin = {
    uuid: "flag-1-pin",
    definition: { at: { position: point(0, 0) } },
    parent: null as null | Record<string, unknown>,
  };
  const secondPin = {
    uuid: "flag-2-pin",
    definition: { at: { position: point(0, 0) } },
    parent: null as null | Record<string, unknown>,
  };
  const makeFlag = (pin: typeof firstPin) => {
    const symbol = {
      typeId: "SchematicSymbol",
      value: "PWR_FLAG",
      lib_symbol: { power: true, library_item_name: "PWR_FLAG" },
      unit_pins: [pin],
    };
    pin.parent = symbol;
    return symbol;
  };
  const first = makeFlag(firstPin);
  const second = makeFlag(secondPin);
  const result = collectSchematicNet(schematic(first, second), { value: "PWR_FLAG" });

  expect(result.items).toEqual(new Set());
  expect(result.netName).toBeUndefined();
});

it("joins pin and label anchors that touch without a wire", () => {
  const firstPin = {
    uuid: "pin-a",
    definition: { at: { position: point(2, 3) } },
    parent: {
      get_symbol_transform: () => ({
        transform: (value: { x: number; y: number }) => value,
      }),
    },
  };
  const secondPin = {
    uuid: "pin-b",
    definition: { at: { position: point(2, 3) } },
    parent: {
      get_symbol_transform: () => ({
        transform: (value: { x: number; y: number }) => value,
      }),
    },
  };
  const net = label("DIRECT", 2, 3);
  const result = collectSchematicNet(schematic(firstPin, secondPin, net), { uuid: "pin-a" });

  expect(result.items).toContain(secondPin);
  expect(result.items).toContain(net);
  expect(result.netName).toBe("DIRECT");
});
