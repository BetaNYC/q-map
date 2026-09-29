import { readFileSync, readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { cleanBody } from "../src/body";
import { parseCap, type CapAlert } from "../src/cap";
import { interpret, toMultiPolygon } from "../src/interpret";

const dir = new URL("./fixtures/cap/", import.meta.url);
const real = Object.fromEntries(
  readdirSync(dir).map((f) => [f.replace(".xml", ""), parseCap(readFileSync(new URL(f, dir), "utf8"))]),
);
const fire = real["2754793634362080"]; // Three Alarm Fire (QN)

describe("parseCap on the five real files", () => {
  it("reads every field the service uses", () => {
    expect(fire).toEqual({
      identifier: "2754793634362080",
      sent: "2026-09-29T05:17:36-04:00",
      status: "Actual",
      msgType: "Alert",
      references: [],
      language: "en-US",
      category: "Fire",
      certainty: "Observed",
      expires: "2026-09-29T07:17:36-04:00",
      headline: "Notify NYC - Three Alarm Fire - Hillside Avenue (QN)",
      description: expect.stringMatching(/^Notification issued 09-29-2026 at 05:17 AM\./),
      areas: [{ areaDesc: "Bronx,Kings,New York,Queens,Staten Island", polygons: [] }],
    });
  });

  it("decodes XML entities in headlines", () => {
    expect(real["2753625403236606"].headline).toBe(
      "Notify NYC - Water Condition - W 177th St & W Tremont Ave (BX)",
    );
  });

  it("rejects a body that is not CAP", () => {
    expect(() => parseCap("<html><body>error</body></html>")).toThrow("not a CAP");
    expect(() => parseCap('<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>1</identifier></alert>')).toThrow(
      "no <info>",
    );
  });

  it("reads identifiers out of <references> triples (unobserved; CAP 1.2 format)", () => {
    const xml = readFileSync(new URL("2754793634362080.xml", dir), "utf8").replace(
      "<msgType>Alert</msgType>",
      "<msgType>Update</msgType><references>111,111,2026-09-29T05:00:00-04:00 222,222,2026-09-29T05:10:00-04:00</references>",
    );
    expect(parseCap(xml)).toMatchObject({ msgType: "Update", references: ["111", "222"] });
  });
});

describe("cleanBody on the five real descriptions", () => {
  const body = (guid: string) => cleanBody(real[guid].description);

  it("drops the 'Notification issued' line from all five", () => {
    for (const guid of Object.keys(real)) {
      expect(body(guid).body).not.toMatch(/Notification issued/);
    }
  });

  it("moves the translations footer to translations_url in the four that have one", () => {
    expect(Object.fromEntries(Object.keys(real).map((g) => [g, body(g).translations_url]))).toEqual({
      "2751666898158459": "http://on.nyc.gov/1OGVGMl",
      "2753625403236606": "http://on.nyc.gov/1kdlCH5",
      "2754793634362080": "http://on.nyc.gov/1kdbhe2",
      "2755652627817500": "http://on.nyc.gov/2hoK0Ij",
      "2758435766629296": null,
    });
    for (const guid of Object.keys(real)) expect(body(guid).body).not.toMatch(/To view this message/);
  });

  it("keeps paragraphs and the NWS relay's line structure, minus stray whitespace", () => {
    expect(body("2755652627817500").body).toBe(
      [
        "The National Weather Service has issued the following:",
        "What: Coastal Flood Statement",
        "Where: Staten Island",
        "When: 9:00 AM on 9/29 to 12:00 Pm on 9/29",
        "Hazards: Inundation of up to one half foot above ground level may cause minor flooding of shore roads and properties.",
        "Preparedness Actions:",
        "- Avoid driving through or coming in contact with flood waters. There could be pollutants in the water or other hazards that you cannot see.",
        "- Coastal flood waters could damage your vehicle. Move your car to higher ground and wash your car thoroughly if it makes contact with flood waters.",
        "- New York City residents, please call 311 if you encounter flooding that makes roads impassable, causes property damage, or persists for more than 48 hours.",
        "",
        "Info: www.weather.gov/okx/.",
      ].join("\n"),
    );
  });

  it("the fire keeps both of its paragraphs", () => {
    expect(body("2754793634362080").body.split("\n\n")).toHaveLength(2);
  });

  it("leaves text it does not recognise alone", () => {
    expect(cleanBody("Something new.\n\nSecond paragraph.")).toEqual({
      body: "Something new.\n\nSecond paragraph.",
      translations_url: null,
    });
  });
});

describe("interpret: the rules on real alerts, altered where the rule is unobserved", () => {
  const at = new Date("2026-09-29T09:30:00Z"); // the fire is live until 11:17 UTC
  const run = (...caps: CapAlert[]) => interpret(caps.map((cap) => ({ guid: cap.identifier, cap })), at);

  it("keeps the real Queens fire", () => {
    expect(run(fire).features).toHaveLength(1);
  });

  it("rule 1: drops Exercise, Test, Draft and System", () => {
    for (const status of ["Exercise", "Test", "Draft", "System"]) {
      const { features, log } = run({ ...fire, status });
      expect(features).toEqual([]);
      expect(log.join()).toMatch(`status ${status}`);
    }
  });

  it("rule 3: an Update replaces what it references; a Cancel removes it and shows nothing", () => {
    const update = { ...fire, identifier: "9001", msgType: "Update", references: [fire.identifier], headline: "Notify NYC - Three Alarm Fire - Hillside Avenue & 160th St (QN)" };
    expect(run(fire, update).features.map((f) => f.properties.id)).toEqual(["9001"]);

    const cancel = { ...fire, identifier: "9002", msgType: "Cancel", references: [fire.identifier] };
    expect(run(fire, cancel).features).toEqual([]);
  });

  it("rule 3: Ack and Error are not alerts", () => {
    expect(run({ ...fire, msgType: "Ack" }).features).toEqual([]);
    expect(run({ ...fire, msgType: "Error" }).features).toEqual([]);
  });

  it("rule 4: drops past expiry, and treats an unparseable expiry as past", () => {
    expect(interpret([{ guid: "x", cap: fire }], new Date("2026-09-29T11:17:36Z")).features).toEqual([]);
    expect(run({ ...fire, expires: "soon" }).features).toEqual([]);
  });

  it("rule 7: drops certainty Unlikely", () => {
    expect(run({ ...fire, certainty: "Unlikely" }).features).toEqual([]);
  });

  it("rule 8: drops another borough, keeps an unknown tag and says so", () => {
    expect(run({ ...fire, headline: "Notify NYC - Three Alarm Fire - Tremont Ave (BX)" }).features).toEqual([]);
    const { features, log } = run({ ...fire, headline: "Notify NYC - Heat Advisory (Long Island)" });
    expect(features[0].properties.scope).toBe("unknown");
    expect(log.join()).toMatch(/unrecognised tag "Long Island"/);
  });

  it("rule 6: geocodes and areaDesc play no part - all five real files name all five boroughs", () => {
    for (const cap of Object.values(real)) {
      expect(cap.areas[0].areaDesc).toBe("Bronx,Kings,New York,Queens,Staten Island");
    }
  });

  it("hazard_slug is null while the table is empty, and the event is logged", () => {
    const { features, log } = run(fire);
    expect(features[0].properties.hazard_slug).toBeNull();
    expect(log.join()).toMatch(/no hazard for event "Three Alarm Fire"/);
  });
});

describe("rule 5: CAP polygons -> GeoJSON (unobserved in the archive)", () => {
  const withPolygons = (...polygons: string[]): CapAlert => ({ ...fire, areas: [{ areaDesc: "", polygons }] });

  it("flips lat,lon to [lon, lat] and closes the ring", () => {
    // The first three points of the August sample's flood advisory polygon.
    expect(toMultiPolygon(withPolygons("40.7298,-73.9375 40.7277,-73.9291 40.7165,-73.9227"))).toEqual({
      type: "MultiPolygon",
      coordinates: [[[[-73.9375, 40.7298], [-73.9291, 40.7277], [-73.9227, 40.7165], [-73.9375, 40.7298]]]],
    });
  });

  it("does not double-close a ring that is already closed", () => {
    const g = toMultiPolygon(withPolygons("40.1,-73.1 40.2,-73.2 40.3,-73.1 40.1,-73.1"));
    expect(g!.coordinates[0][0]).toHaveLength(4);
  });

  it("keeps several polygons as one MultiPolygon; skips unreadable and degenerate rings", () => {
    const log: string[] = [];
    const g = toMultiPolygon(
      withPolygons("40.1,-73.1 40.2,-73.2 40.3,-73.1", "garbage", "40.1,-73.1 40.2,-73.2", "40.5,-73.5 40.6,-73.6 40.7,-73.5"),
      log,
    );
    expect(g!.coordinates).toHaveLength(2);
    expect(log).toHaveLength(2);
  });

  it("no polygons -> null geometry, as in all five real alerts", () => {
    expect(toMultiPolygon(fire)).toBeNull();
  });
});
