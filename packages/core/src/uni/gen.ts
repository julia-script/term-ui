import {
  readFileSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { camelCase, upperFirst } from "lodash-es";
import { dedent } from "ts-dedent";

const upperCamelCase = (str: string) =>
  upperFirst(camelCase(str));
import { existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
const __dirname = dirname(
  fileURLToPath(import.meta.url),
);

const files: {
  path: string;
  url: string;
  type: "bool" | "enum";
  defaultValue: boolean | string;
  name: string;
}[] = [
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/auxiliary/GraphemeBreakProperty.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/auxiliary/GraphemeBreakProperty.txt",
    type: "enum",
    defaultValue: "Other",
    name: "GraphemeBreak",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/auxiliary/WordBreakProperty.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/auxiliary/WordBreakProperty.txt",
    type: "enum",
    defaultValue: "Other",
    name: "WordBreak",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/auxiliary/SentenceBreakProperty.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/auxiliary/SentenceBreakProperty.txt",
    type: "enum",
    defaultValue: "Other",
    name: "SentenceBreak",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/extracted/DerivedLineBreak.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedLineBreak.txt",
    type: "enum",
    defaultValue: "XX",
    name: "LineBreak",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/emoji/emoji-data.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt",
    type: "bool",
    defaultValue: true,
    name: "Emoji",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/DerivedCoreProperties.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/DerivedCoreProperties.txt",
    type: "enum",
    defaultValue: "none",
    name: "CoreProperty",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/extracted/DerivedEastAsianWidth.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedEastAsianWidth.txt",
    type: "enum",
    defaultValue: "N",
    name: "EastAsianWidth",
  },
  {
    path: path.join(
      __dirname,
      "data/16.0.0/ucd/extracted/DerivedGeneralCategory.txt",
    ),
    url: "https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedGeneralCategory.txt",
    type: "enum",
    defaultValue: "X",
    name: "GeneralCategory",
  },
];

async function downloadFiles() {
  for (const file of files) {
    if (existsSync(file.path)) {
      console.log(
        `✔ Already exists, skipping: ${file.path}`,
      );
      continue;
    }

    const dir = dirname(file.path);
    mkdirSync(dir, { recursive: true });

    try {
      const response = await fetch(file.url);
      if (!response.ok) {
        console.error(
          `✖ Failed to download ${file.url}: ${response.statusText}`,
        );
        continue;
      }

      const content = await response.text();
      writeFileSync(file.path, content, "utf8");
      console.log(`⬇ Downloaded: ${file.path}`);
    } catch (error) {
      console.error(
        `✖ Error downloading ${file.url}:`,
        error,
      );
    }
  }

  console.log(
    "✨ Unicode data files check complete.",
  );
}
/**
 * Return smallest possible integer size for the given array.
 */
const max = (numbers: number[]): number => {
  let max = Number.MIN_SAFE_INTEGER;
  for (const number of numbers) {
    if (number > max) {
      max = number;
    }
  }
  return max;
};
function getsize(data: number[]): number {
  const maxdata = max(data);
  if (maxdata < 0x100) {
    return 1;
  }
  if (maxdata < 0x10000) {
    return 2;
  }
  return 4;
}

/**
 * Split a table to save space.
 * This function can be useful to save space if many of the ints are the same.
 * t1 and t2 are arrays of ints, and shift is an int, chosen to minimize the
 * combined size of t1 and t2 (in Zig code), and where for each i in range(len(t)),
 * t[i] == t2[(t1[i >> shift] << shift) + (i & mask)]
 * where mask is a bitmask isolating the last "shift" bits.
 */
function splitbins(
  t: number[],
): [number[], number[], number] {
  let n = t.length - 1; // last valid index
  let maxshift = 0; // the most we can shift n and still have something left
  if (n > 0) {
    while (n >> 1) {
      n >>= 1;
      maxshift += 1;
    }
  }

  let bytes = Number.MAX_SAFE_INTEGER; // smallest total size so far
  let best: [number[], number[], number] = [
    [],
    [],
    0,
  ];

  for (
    let shift = 0;
    shift <= maxshift;
    shift++
  ) {
    const t1: number[] = [];
    const t2: number[] = [];
    const size = 2 ** shift;
    const bincache: Map<string, number> =
      new Map();

    for (let i = 0; i < t.length; i += size) {
      // Create bin as a slice of the original array
      const bin = t.slice(i, i + size);

      const binKey = bin.join(",");

      let index = bincache.get(binKey);
      if (typeof index === "undefined") {
        index = t2.length;
        bincache.set(binKey, index);

        // Add all elements from bin to t2 without using spread
        for (let j = 0; j < bin.length; j++) {
          t2.push(bin[j]); // Add all elements, including any undefined values
        }
      }
      t1.push(index >> shift);
    }

    // determine memory size
    const b =
      t1.length * getsize(t1) +
      t2.length * getsize(t2);
    if (b < bytes) {
      best = [t1, t2, shift];
      bytes = b;
    }
  }

  return best;
}

/**
 * Parse UCD property files and extract code point properties
 */
function iterCodePointProperties(
  content: string,
): Array<[number, { fields: string[] }]> {
  const result: Array<
    [number, { fields: string[] }]
  > = [];
  const lines = content.split("\n");

  for (const line of lines) {
    // Skip comments and empty lines
    if (
      line.trim() === "" ||
      line.startsWith("#")
    ) {
      continue;
    }

    // Remove comments at the end of line
    const commentPos = line.indexOf("#");
    const actualLine =
      commentPos >= 0
        ? line.substring(0, commentPos)
        : line;

    // Parse the line
    const parts = actualLine
      .split(";")
      .map((part) => part.trim());

    // Handle code point ranges (e.g., 0000..007F)
    if (parts.length > 0) {
      const codePointPart = parts[0];
      if (codePointPart?.includes("..")) {
        const rangeParts =
          codePointPart.split("..");
        if (
          rangeParts.length === 2 &&
          rangeParts[0] &&
          rangeParts[1]
        ) {
          const start = Number.parseInt(
            rangeParts[0],
            16,
          );
          const end = Number.parseInt(
            rangeParts[1],
            16,
          );
          if (
            !Number.isNaN(start) &&
            !Number.isNaN(end)
          ) {
            for (
              let cp = start;
              cp <= end;
              cp++
            ) {
              result.push([
                cp,
                {
                  fields: [
                    parts.slice(1).join("_"),
                  ],
                },
              ]);
            }
          }
        }
      } else if (codePointPart) {
        const cp = Number.parseInt(
          codePointPart,
          16,
        );
        if (!Number.isNaN(cp)) {
          result.push([
            cp,
            {
              fields: [parts.slice(1).join("_")],
            },
          ]);
        }
      }
    }
  }

  return result;
}

/**
 * Group items by a key function
 */
function groupBy<
  T,
  K extends string | number | symbol,
>(
  items: T[],
  keyFn: (item: T) => K,
): Map<K, T[]> {
  const result = new Map<K, T[]>();

  for (const item of items) {
    const key = keyFn(item);
    if (!result.has(key)) {
      result.set(key, []);
    }
    const group = result.get(key);
    if (group) {
      group.push(item);
    }
  }

  return result;
}

/**
 * Sort string arrays lexicographically to match Python's tuple sorting
 */
function compareStringArrays(
  a: string[],
  b: string[],
): number {
  const minLength = Math.min(a.length, b.length);

  for (let i = 0; i < minLength; i++) {
    const aVal = a[i] || "";
    const bVal = b[i] || "";
    if (aVal < bVal) return -1;
    if (aVal > bVal) return 1;
  }

  return a.length - b.length;
}

/**
 * Main function
 */
async function main() {
  // Process properties
  const names: string[] = [];
  const maxUnicode = 0x10ffff; // Maximum Unicode code point (full range)
  const db: Array<string[]> = [];
  for (let i = 0; i <= maxUnicode; i++) {
    db.push([]);
  }

  const columnMap: Record<
    string,
    | {
        type: "bool";
        list: boolean[];
        index: number;
      }
    | {
        type: "enum";
        list: string[];
        index: number;
      }
  > = {};

  for (const file of files) {
    const content = readFileSync(
      file.path,
      "utf-8",
    );
    const items =
      iterCodePointProperties(content);

    // Convert items to a dictionary for faster lookup
    const itemDict = new Map(items);
    if (file.type === "bool") {
      const map = new Map<string, boolean[]>();
      for (const [cp, record] of items) {
        for (const field of record.fields) {
          if (!map.has(field)) {
            map.set(
              field,
              new Array(maxUnicode + 1).fill(
                false,
              ),
            );
          }
          const values = map.get(field);
          if (!values) {
            throw new Error(
              "values is undefined",
            );
          }
          values[cp] = true;
        }
      }

      for (const [
        field,
        values,
      ] of map.entries()) {
        names.push(field);
        columnMap[field] = {
          index: names.length - 1,
          type: "bool",
          list: values,
        };
      }

      continue;
    }
    if (file.type === "enum") {
      names.push(file.name);
      if (!file.defaultValue) {
        throw new Error(
          `Invalid property name: ${file.name}`,
        );
      }

      columnMap[file.name] = {
        index: names.length - 1,
        type: "enum",
        list: new Array(maxUnicode + 1).fill(
          file.defaultValue,
        ),
      };
      for (let cp = 0; cp <= maxUnicode; cp++) {
        const record = itemDict.get(cp);
        const value =
          record?.fields[0] ?? file.defaultValue;

        columnMap[file.name].list[cp] = value;
      }
    }
  }

  const indexPool = new Map<string, number>();
  const indices2: number[] = new Array(
    maxUnicode + 1,
  ).fill(0);
  const table: (boolean | string)[][] = [];
  for (let cp = 0; cp <= maxUnicode; cp++) {
    const row: (boolean | string)[] = [];
    for (const [
      name,
      { type, list },
    ] of Object.entries(columnMap)) {
      row.push(list[cp] ?? "");
    }
    const key = row.join(",");

    let index = indexPool.get(key);

    if (index === undefined) {
      index = indexPool.size;
      indexPool.set(key, index);
      table.push(row);
    }
    indices2[cp] = index;
  }
  // console.log(indices2)
  const [index1, index2, shift] =
    splitbins(indices2);
  console.log(index1, index2, shift);
  const shiftZigCode = dedent`
	pub const shift: usize = ${shift};
	`;
  const index1ZigCode = dedent`
	pub const index1 = [_]u9{
		${index1.map((val) => `${val}`).join(", ")}
	};
	`;

  const index2ZigCode = dedent`
  pub const index2 = [_]u9{
    ${index2.map((val) => `${val}`).join(", ")}
  };
  `;

  const valuesZigCode = dedent`
  pub const values = [_]Columns{
    ${table.map((record) => `    .{ ${record.map((val) => (typeof val === "boolean" ? JSON.stringify(val) : `.${val}`)).join(", ")} },`).join("\n")}
  };
  `;
  let types = "";
  for (const [
    name,
    { type, list },
  ] of Object.entries(columnMap)) {
    if (type === "enum") {
      const unique = [...new Set(list)];
      types += dedent`
      pub const ${upperCamelCase(name)} = enum {
        ${unique.map((val) => `${val}`).join(",\n")},
      };
      `;
      types += "\n";
    } else {
      types += `pub const ${upperCamelCase(name)}Index: usize = ${columnMap[name].index};\n`;
    }
  }

  const columnsTuple = dedent`
  pub const Columns = struct {${names.map((name) => (columnMap[name]?.type === "bool" ? "bool" : `${upperCamelCase(name)}`)).join(", ")}};
  `;
  const zigCode = dedent`
  ${types}
  ${columnsTuple}
  ${valuesZigCode}
  ${shiftZigCode}
  ${index1ZigCode}
  ${index2ZigCode}

  `;

  writeFileSync(
    path.join(__dirname, "lookups.zig"),
    zigCode,
  );
  console.error(
    `Output written to ${path.join(__dirname, "lookups.zig")}`,
  );
}

await downloadFiles();
await main();
