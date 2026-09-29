import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { parseHeadline, scopeOf } from "../src/headline";

describe("the five real headlines (archive, 2026-09-28/29)", () => {
  it.each([
    [
      "Notify NYC - Water Condition - W 177th St & W Tremont Ave (BX)",
      { event: "Water Condition", location: "W 177th St & W Tremont Ave", scope: "other", tag: "BX" },
    ],
    [
      "Notify NYC - Three Alarm Fire - Hillside Avenue (QN)",
      { event: "Three Alarm Fire", location: "Hillside Avenue", scope: "queens", tag: "QN" },
    ],
    [
      "Notify NYC - Coastal Flood Statement - 9/29 (Staten Island)",
      { event: "Coastal Flood Statement", location: null, scope: "other", tag: "Staten Island" },
    ],
    [
      "Notify NYC - Waterbody Advisory (NYC)",
      { event: "Waterbody Advisory", location: null, scope: "citywide", tag: "NYC" },
    ],
    [
      "Notify NYC - Police Activity - Cross Bay Boulevard (QN)",
      { event: "Police Activity", location: "Cross Bay Boulevard", scope: "queens", tag: "QN" },
    ],
  ])("%s", (headline, expected) => {
    expect(parseHeadline(headline)).toEqual(expected);
  });
});

// Every English headline the recorder has ever archived must parse to a
// recognised scope. This is the check that grows with the data: a new tag
// spelling fails here, on the next Worker PR, instead of silently becoming
// 'unknown' in production. Fix it by adding the tag to TAGS in headline.ts.
describe("every archived English headline", () => {
  const items = new URL("../../../data/archive/alerts/items.csv", import.meta.url);
  const titles = existsSync(items) ? englishTitles(readFileSync(items, "utf8")) : [];

  it.skipIf(titles.length === 0)("parses to an event and a recognised scope", () => {
    const failures = titles
      .map((title) => ({ title, parsed: parseHeadline(title) }))
      .filter(({ parsed }) => parsed.event === null || parsed.scope === "unknown");
    expect(failures).toEqual([]);
  });
});

describe("unobserved shapes", () => {
  it("an unrecognised tag is 'unknown' - kept, not dropped", () => {
    expect(parseHeadline("Notify NYC - Heat Advisory (Long Island)")).toMatchObject({
      event: "Heat Advisory",
      scope: "unknown",
      tag: "Long Island",
    });
  });

  it("a headline outside the grammar is 'unknown' with nothing parsed", () => {
    expect(parseHeadline("Heat Advisory for NYC")).toEqual({
      event: null,
      location: null,
      scope: "unknown",
      tag: null,
    });
    expect(parseHeadline("Notify NYC - Heat Advisory")).toMatchObject({ scope: "unknown" });
  });

  it("a location holding ' - ' is kept whole", () => {
    expect(parseHeadline("Notify NYC - Road Closure - Grand Central Pkwy - Exit 9 (QN)").location).toBe(
      "Grand Central Pkwy - Exit 9",
    );
  });

  it("a bare hyphen does not split", () => {
    expect(parseHeadline("Notify NYC - Hi-Rise Fire - Far Rockaway (QN)").event).toBe("Hi-Rise Fire");
  });

  it("only the last parenthesised group is the tag", () => {
    expect(parseHeadline("Notify NYC - Water Main Break - 69th St (Woodside) (QN)")).toMatchObject({
      location: "69th St (Woodside)",
      scope: "queens",
    });
  });

  it("tolerates non-breaking spaces and stray whitespace", () => {
    expect(parseHeadline("Notify NYC - Police Activity  -  Jamaica Ave ( QN )")).toMatchObject({
      event: "Police Activity",
      location: "Jamaica Ave",
      scope: "queens",
    });
  });

  it.each([
    ["QN & BK", "queens"],
    ["Brooklyn/Queens", "queens"],
    ["Bronx and Manhattan", "other"],
    ["NYC, SI", "citywide"],
    ["BX & Long Island", "unknown"],
    ["The Bronx", "other"],
    ["queens.", "queens"],
  ])("tag %s -> %s", (tag, scope) => {
    expect(scopeOf(tag)).toBe(scope);
  });
});

/** English titles from items.csv. Titles may be quoted and contain commas. */
function englishTitles(csv: string): string[] {
  const [header, ...lines] = csv.trim().split("\n").map(parseCsvLine);
  const author = header.indexOf("author");
  const title = header.indexOf("title");
  return lines.filter((row) => row[author] === "NYCEM [English]").map((row) => row[title]);
}

function parseCsvLine(line: string): string[] {
  const fields: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"' && line[i + 1] === '"') (field += '"'), i++;
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") fields.push(field), (field = "");
    else field += c;
  }
  fields.push(field);
  return fields;
}
