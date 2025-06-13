import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import {
  SelectionExtendDirection,
  SelectionExtendGranularity,
} from "./constants";
import { initFromFile } from "./node";
const dirpath = dirname(
  fileURLToPath(import.meta.url),
);

const mod = await initFromFile(
  join(dirpath, "../zig-out/bin/core-debug.wasm"),
  {
    logFn: console.log,
  },
);

describe("Selection operations", () => {
  test("should extend by line", () => {
    const tree = mod.Tree_init();
    const root = mod.Tree_createNode(tree, "");
    const first_line = mod.Tree_createTextNode(
      tree,
      "First line",
    );
    const second_line = mod.Tree_createTextNode(
      tree,
      "Second line",
    );
    const third_line = mod.Tree_createTextNode(
      tree,
      "Third line",
    );
    mod.Tree_appendChild(tree, root, first_line);
    mod.Tree_appendChild(tree, root, second_line);
    mod.Tree_appendChild(tree, root, third_line);
    mod.Tree_computeLayout(
      tree,
      "30",
      "max-content",
    );

    const selection = mod.Tree_createSelection(
      tree,
      first_line,
      5,
      first_line,
      5,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: first_line,
      offset: 5,
    });
    mod.Selection_extendBy(
      tree,
      selection,
      SelectionExtendGranularity.line,
      SelectionExtendDirection.forward,
      5,
      0,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: second_line,
      offset: 5,
    });

    mod.Selection_extendBy(
      tree,
      selection,
      SelectionExtendGranularity.line,
      SelectionExtendDirection.forward,
      5,
      0,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: third_line,
      offset: 5,
    });
    // no more lines, so it should go to the end of the last line
    mod.Selection_extendBy(
      tree,
      selection,
      SelectionExtendGranularity.line,
      SelectionExtendDirection.forward,
      5,
      0,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: third_line,
      offset: 10,
    });
    // if thats the end, nothing should happen
    mod.Selection_extendBy(
      tree,
      selection,
      SelectionExtendGranularity.line,
      SelectionExtendDirection.forward,
      5,
      0,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: third_line,
      offset: 10,
    });
    // if we go back, it should go to end of the second line
    mod.Selection_extendBy(
      tree,
      selection,
      SelectionExtendGranularity.line,
      SelectionExtendDirection.backward,
      5,
      0,
    );
    expect(
      mod.Selection_getFocus(tree, selection),
    ).toEqual({
      node: second_line,
      offset: 10,
    });

    mod.Tree_deinit(tree);
  });
});
