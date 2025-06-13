import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { cursorShapes } from "@term-ui/shared/cmd/cursor-shape";
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
} from "vitest";
import { initFromFile } from "./node.js";
import type { Module } from "./node.js";
const dirpath = dirname(
  fileURLToPath(import.meta.url),
);

const mod = await initFromFile(
  join(dirpath, "../zig-out/bin/core-debug.wasm"),
  {
    // writeStream: process.stdout,
    // logFn: () => {},
    logFn: console.log,
  },
);

let tree: number;
const initTreeHook = () =>
  beforeEach(async () => {
    tree = mod.Tree_init();
    return () => {
      mod.Tree_deinit(tree);
      expect(mod.detectLeaks()).toBe(false);
    };
  });

describe("Node creation and destruction", () => {
  initTreeHook();
  it("should create and destroy nodes", () => {
    const node = mod.Tree_createNode(
      tree,
      "background-color: red;",
    );
    expect(
      mod.Tree_doesNodeExist(tree, node),
    ).toBe(true);
    mod.Tree_destroyNode(tree, node);
    expect(
      mod.Tree_doesNodeExist(tree, node),
    ).toBe(false);
  });

  it("should create text nodes", () => {
    const textNode = mod.Tree_createTextNode(
      tree,
      "Hello World",
    );
    expect(
      mod.Tree_doesNodeExist(tree, textNode),
    ).toBe(true);
  });
});
describe("Tree hierarchy operations", () => {
  initTreeHook();
  it("should append child to parent", () => {
    const parent = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");
    mod.Tree_appendChild(tree, parent, child);

    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(1);
    expect(
      mod.Tree_getNodeParent(tree, child),
    ).toBe(parent);
  });

  it("should insert child before another child", () => {
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");
    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_insertBefore(tree, child2, child1);

    const childrenCount =
      mod.Tree_getChildrenCount(tree, parent);
    expect(childrenCount).toBe(2);
    const children = new Uint32Array(
      mod.memory.buffer,
      mod.Tree_getChildren(tree, parent),
      childrenCount,
    );
    console.log([...children]);
    expect([...children]).toMatchObject([
      child2,
      child1,
    ]);
  });

  it("should append child at specific index", () => {
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");
    const child3 = mod.Tree_createNode(tree, "");

    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);
    mod.Tree_appendChildAtIndex(
      tree,
      parent,
      child3,
      1,
    );

    const children = new Uint32Array(
      mod.memory.buffer,
      mod.Tree_getChildren(tree, parent),
      mod.Tree_getChildrenCount(tree, parent),
    );
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(3);
    expect(children[0]).toBe(child1);
    expect(children[1]).toBe(child3);
    expect(children[2]).toBe(child2);
  });

  it("should remove child", () => {
    const parent = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");
    mod.Tree_appendChild(tree, parent, child);

    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(1);

    mod.Tree_removeChild(tree, parent, child);
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(0);
    expect(
      mod.Tree_doesNodeExist(tree, child),
    ).toBe(true);
  });

  it("should remove all children", () => {
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");

    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);

    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(2);

    mod.Tree_removeChildren(tree, parent);
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(0);
    expect(
      mod.Tree_doesNodeExist(tree, child1),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, child2),
    ).toBe(true);
  });

  it("should check if node is attached", () => {
    const root = mod.Tree_createNode(tree, "");
    const parent = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");
    const detachedNode = mod.Tree_createNode(
      tree,
      "",
    );

    mod.Tree_appendChild(tree, parent, child);

    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        parent,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        detachedNode,
      ),
    ).toBe(false);

    // Attach parent to root
    mod.Tree_appendChild(tree, root, parent);

    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        parent,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        detachedNode,
      ),
    ).toBe(false);
  });
});

describe("Style operations", () => {
  initTreeHook();
  it("should set style", () => {
    const node = mod.Tree_createNode(tree, "");
    mod.Tree_setStyle(
      tree,
      node,
      "background-color: blue; width: 100;",
    );

    // We can't directly check the style value, but we can compute layout and check dimensions
    mod.Tree_computeLayout(tree, "200", "200");

    expect(
      mod.Tree_getNodeClientWidth(tree, node),
    ).toBe(100);
  });

  it("should set style property", () => {
    const node = mod.Tree_createNode(tree, "");
    mod.Tree_setStyleProperty(
      tree,
      node,
      "width",
      "150px",
    );

    mod.Tree_computeLayout(tree, "200", "200");

    expect(
      mod.Tree_getNodeClientWidth(tree, node),
    ).toBe(150);
  });

  it("should get node cursor style", () => {
    let i = 0;
    const node = mod.Tree_createNode(tree, "");
    mod.Tree_appendChild(
      tree,
      node,
      mod.Tree_createTextNode(tree, ""),
    );
    for (const shape of cursorShapes) {
      mod.Tree_setStyle(
        tree,
        node,
        `cursor: ${shape};`,
      );
      mod.Tree_computeLayout(tree, "200", "200");
      const cursorStyle =
        mod.Tree_getNodeCursorStyle(tree, node);

      expect(cursorStyle).toBe(i);

      i++;
    }
  });
});

describe("Text operations", () => {
  initTreeHook();
  it("should set text", () => {
    const textNode = mod.Tree_createTextNode(
      tree,
      "Original text",
    );
    mod.Tree_setText(
      tree,
      textNode,
      "Updated text",
    );

    expect(textNode).toBe(0);
    // We can't directly check the text content without a getter method,
    // but we can at least verify the node still exists
    expect(
      mod.Tree_doesNodeExist(tree, textNode),
    ).toBe(true);
  });
});

describe("Layout operations", () => {
  initTreeHook();
  it("should compute layout", () => {
    const node = mod.Tree_createNode(
      tree,
      "width: 120px; height: 80px;",
    );

    mod.Tree_computeLayout(tree, "300", "200");

    expect(
      mod.Tree_getNodeClientWidth(tree, node),
    ).toBe(120);
    expect(
      mod.Tree_getNodeClientHeight(tree, node),
    ).toBe(80);
  });

  it("should get node dimensions", () => {
    const parent = mod.Tree_createNode(
      tree,
      "width: 200px; height: 150px;",
    );
    const child = mod.Tree_createNode(
      tree,
      "width: 100px; height: 50px;",
    );

    mod.Tree_appendChild(tree, parent, child);
    mod.Tree_computeLayout(tree, "300", "200");

    expect(
      mod.Tree_getNodeClientWidth(tree, parent),
    ).toBe(200);
    expect(
      mod.Tree_getNodeClientHeight(tree, parent),
    ).toBe(150);
    expect(
      mod.Tree_getNodeClientWidth(tree, child),
    ).toBe(100);
    expect(
      mod.Tree_getNodeClientHeight(tree, child),
    ).toBe(50);
  });
});

describe("Scroll operations", () => {
  initTreeHook();
  it("should set and get scroll position", () => {
    const node = mod.Tree_createNode(
      tree,
      "width: 200px; height: 200px; overflow: scroll;",
    );
    const content = mod.Tree_createNode(
      tree,
      "width: 400px; height: 400px;",
    );

    mod.Tree_appendChild(tree, node, content);
    mod.Tree_computeLayout(tree, "300", "300");

    mod.Tree_setNodeScrollTop(tree, node, 50);
    mod.Tree_setNodeScrollLeft(tree, node, 25);

    expect(
      mod.Tree_getNodeScrollTop(tree, node),
    ).toBe(50);
    expect(
      mod.Tree_getNodeScrollLeft(tree, node),
    ).toBe(25);
  });

  it("should get scroll dimensions", () => {
    const node = mod.Tree_createNode(
      tree,
      "width: 100px; height: 100px; overflow: scroll;",
    );
    const content = mod.Tree_createNode(
      tree,
      "width: 300px; height: 200px;",
    );

    mod.Tree_appendChild(tree, node, content);
    mod.Tree_computeLayout(tree, "300", "300");

    expect(
      mod.Tree_getNodeScrollWidth(tree, node),
    ).toBe(300);
    expect(
      mod.Tree_getNodeScrollHeight(tree, node),
    ).toBe(200);
  });
});

describe("Node type operations", () => {
  initTreeHook();
  it("should get node kind", () => {
    const regularNode = mod.Tree_createNode(
      tree,
      "",
    );
    const textNode = mod.Tree_createTextNode(
      tree,
      "Text content",
    );

    const regularNodeKind = mod.Tree_getNodeKind(
      tree,
      regularNode,
    );
    const textNodeKind = mod.Tree_getNodeKind(
      tree,
      textNode,
    );

    // The exact values depend on the enum definition in the Zig code
    expect(regularNodeKind).not.toBe(
      textNodeKind,
    );
  });
});

describe("Input manager operations", () => {
  initTreeHook();
  it("should enable and disable input manager", () => {
    // Just testing the methods don't throw
    expect(() => {
      mod.Tree_enableInputManager(tree);
      mod.Tree_disableInputManager(tree);
    }).not.toThrow();
  });
});

it("should output tree structure with dump", () => {
  // Tree_dump outputs to console log, so we're just testing it doesn't throw
  // expect(() => mod.Tree_dump(tree)).not.toThrow();
});

describe("Node destruction and memory management", () => {
  initTreeHook();
  it("should destroy node recursively", () => {
    // Create a complex hierarchy
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");
    const grandchild1 = mod.Tree_createNode(
      tree,
      "",
    );
    const grandchild2 = mod.Tree_createNode(
      tree,
      "",
    );

    // Set up hierarchy
    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);
    mod.Tree_appendChild(
      tree,
      child1,
      grandchild1,
    );
    mod.Tree_appendChild(
      tree,
      child2,
      grandchild2,
    );

    // // Verify all nodes exist
    expect(
      mod.Tree_doesNodeExist(tree, parent),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, child1),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, child2),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, grandchild1),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, grandchild2),
    ).toBe(true);

    // // Destroy the parent node recursively
    mod.Tree_destroyNodeRecursive(tree, parent);

    // // Verify all nodes are gone
    expect(
      mod.Tree_doesNodeExist(tree, parent),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child1),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child2),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, grandchild1),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, grandchild2),
    ).toBe(false);
  });

  it("should destroy node without affecting detached nodes", () => {
    // Create a node structure
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");
    const detachedNode = mod.Tree_createNode(
      tree,
      "",
    );

    // Set up hierarchy
    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);

    // Destroy parent node
    mod.Tree_destroyNode(tree, parent);

    // Verify parent is gone
    expect(
      mod.Tree_doesNodeExist(tree, parent),
    ).toBe(false);

    // Verify children still exist (they're detached but not destroyed)
    expect(
      mod.Tree_doesNodeExist(tree, child1),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, child2),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, detachedNode),
    ).toBe(true);

    // Verify children are detached (no parent)
    expect(
      mod.Tree_getNodeParent(tree, child1),
    ).toBe(-1);
    expect(
      mod.Tree_getNodeParent(tree, child2),
    ).toBe(-1);
  });

  it("should maintain correct node existence after complex operations", () => {
    // Create multiple nodes and store in a fixed-size array with known indices
    const nodes = Array(10).fill(0);
    for (let i = 0; i < 10; i++) {
      nodes[i] = mod.Tree_createNode(tree, "");
    }

    // Create hierarchy
    for (let i = 1; i < 10; i++) {
      mod.Tree_appendChild(
        tree,
        nodes[0],
        nodes[i],
      );
    }

    // Verify all nodes exist
    for (const node of nodes) {
      expect(
        mod.Tree_doesNodeExist(tree, node),
      ).toBe(true);
    }

    // Remove some nodes
    mod.Tree_destroyNode(tree, nodes[3]);
    mod.Tree_destroyNode(tree, nodes[5]);
    mod.Tree_destroyNode(tree, nodes[7]);

    // Verify correct nodes exist/don't exist
    expect(
      mod.Tree_doesNodeExist(tree, nodes[0]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[1]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[2]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[3]),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[4]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[5]),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[6]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[7]),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[8]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[9]),
    ).toBe(true);

    // Remove parent node (should not destroy children)
    mod.Tree_destroyNode(tree, nodes[0]);

    // Verify parent is gone
    expect(
      mod.Tree_doesNodeExist(tree, nodes[0]),
    ).toBe(false);

    // Verify remaining children still exist
    expect(
      mod.Tree_doesNodeExist(tree, nodes[1]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[2]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[4]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[6]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[8]),
    ).toBe(true);
    expect(
      mod.Tree_doesNodeExist(tree, nodes[9]),
    ).toBe(true);
  });

  it("should compare regular destroy vs recursive destroy", () => {
    // Create a parent with two children
    const parent1 = mod.Tree_createNode(tree, "");
    const child1A = mod.Tree_createNode(tree, "");
    const child1B = mod.Tree_createNode(tree, "");

    mod.Tree_appendChild(tree, parent1, child1A);
    mod.Tree_appendChild(tree, parent1, child1B);

    // Create another parent with two children
    const parent2 = mod.Tree_createNode(tree, "");
    const child2A = mod.Tree_createNode(tree, "");
    const child2B = mod.Tree_createNode(tree, "");

    mod.Tree_appendChild(tree, parent2, child2A);
    mod.Tree_appendChild(tree, parent2, child2B);

    // Use regular destroy on parent1
    mod.Tree_destroyNode(tree, parent1);

    // Use recursive destroy on parent2
    mod.Tree_destroyNodeRecursive(tree, parent2);

    // Check parent1's status
    expect(
      mod.Tree_doesNodeExist(tree, parent1),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child1A),
    ).toBe(true); // Children still exist
    expect(
      mod.Tree_doesNodeExist(tree, child1B),
    ).toBe(true);

    // Check parent2's status
    expect(
      mod.Tree_doesNodeExist(tree, parent2),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child2A),
    ).toBe(false); // Children are destroyed
    expect(
      mod.Tree_doesNodeExist(tree, child2B),
    ).toBe(false);
  });

  it("should remove deleted node from parent's children list", () => {
    // Create a parent with multiple children
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");
    const child3 = mod.Tree_createNode(tree, "");

    // Set up hierarchy
    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);
    mod.Tree_appendChild(tree, parent, child3);

    // Verify initial state
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(3);

    const childrenBeforeDelete = new Uint32Array(
      mod.memory.buffer,
      mod.Tree_getChildren(tree, parent),
      mod.Tree_getChildrenCount(tree, parent),
    );

    // Verify child2 is in parent's children array
    expect(
      Array.from(childrenBeforeDelete).includes(
        child2,
      ),
    ).toBe(true);

    // Delete child2
    mod.Tree_destroyNode(tree, child2);

    // Verify parent now has only 2 children
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(2);

    // Get updated children array
    const childrenAfterDelete = new Uint32Array(
      mod.memory.buffer,
      mod.Tree_getChildren(tree, parent),
      mod.Tree_getChildrenCount(tree, parent),
    );

    // Verify child2 is no longer in parent's children array
    expect(
      Array.from(childrenAfterDelete).includes(
        child2,
      ),
    ).toBe(false);

    // Verify other children are still there
    expect(
      Array.from(childrenAfterDelete).includes(
        child1,
      ),
    ).toBe(true);
    expect(
      Array.from(childrenAfterDelete).includes(
        child3,
      ),
    ).toBe(true);
  });

  it("should update parent's children list when a node is destroyed recursively", () => {
    // Create a multi-level hierarchy
    const root = mod.Tree_createNode(tree, "");
    const parent = mod.Tree_createNode(tree, "");
    const child1 = mod.Tree_createNode(tree, "");
    const child2 = mod.Tree_createNode(tree, "");

    // Set up hierarchy
    mod.Tree_appendChild(tree, root, parent);
    mod.Tree_appendChild(tree, parent, child1);
    mod.Tree_appendChild(tree, parent, child2);

    // Verify initial state
    expect(
      mod.Tree_getChildrenCount(tree, root),
    ).toBe(1);
    expect(
      mod.Tree_getChildrenCount(tree, parent),
    ).toBe(2);

    // Destroy parent recursively (should destroy children too)
    mod.Tree_destroyNodeRecursive(tree, parent);

    // Verify parent is no longer in root's children
    expect(
      mod.Tree_getChildrenCount(tree, root),
    ).toBe(0);

    // Verify nodes don't exist anymore
    expect(
      mod.Tree_doesNodeExist(tree, parent),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child1),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, child2),
    ).toBe(false);
  });
});

describe("Node attachment and detachment", () => {
  initTreeHook();
  it("should properly track node attachment status", () => {
    const root = mod.Tree_createNode(tree, "");
    const parent = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");
    const grandchild = mod.Tree_createNode(
      tree,
      "",
    );

    // Initially, no nodes are attached
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        parent,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        grandchild,
      ),
    ).toBe(false);

    // Attach parent -> child -> grandchild
    mod.Tree_appendChild(tree, parent, child);
    mod.Tree_appendChild(tree, child, grandchild);

    // Still not attached to root
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        parent,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        grandchild,
      ),
    ).toBe(false);

    // Connect parent to root
    mod.Tree_appendChild(tree, root, parent);

    // Now they should all be attached to root
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        parent,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        grandchild,
      ),
    ).toBe(true);

    // Check attachments to parent
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent,
        child,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent,
        grandchild,
      ),
    ).toBe(true);

    // Check attachments to child
    expect(
      mod.Tree_getNodeContains(
        tree,
        child,
        grandchild,
      ),
    ).toBe(true);
  });

  it("should handle tree modifications and attachment status correctly", () => {
    const root = mod.Tree_createNode(tree, "");
    const branch1 = mod.Tree_createNode(tree, "");
    const branch2 = mod.Tree_createNode(tree, "");
    const leaf1 = mod.Tree_createNode(tree, "");
    const leaf2 = mod.Tree_createNode(tree, "");

    // Create tree structure
    mod.Tree_appendChild(tree, root, branch1);
    mod.Tree_appendChild(tree, root, branch2);
    mod.Tree_appendChild(tree, branch1, leaf1);
    mod.Tree_appendChild(tree, branch2, leaf2);

    // Verify initial attachments
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        branch1,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        branch2,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf1),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf2),
    ).toBe(true);

    // Move leaf1 from branch1 to branch2
    mod.Tree_removeChild(tree, branch1, leaf1);
    mod.Tree_appendChild(tree, branch2, leaf1);

    // Verify leaf1 is still attached (through branch2 now)
    expect(
      mod.Tree_getNodeContains(tree, root, leaf1),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf1,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        leaf1,
      ),
    ).toBe(true);

    // Detach branch1 completely
    mod.Tree_removeChild(tree, root, branch1);

    // Verify branch1 is no longer attached, but still exists
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        branch1,
      ),
    ).toBe(false);
    expect(
      mod.Tree_doesNodeExist(tree, branch1),
    ).toBe(true);

    // branch2 and its children should still be attached
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        branch2,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf2),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf1),
    ).toBe(true);
  });

  it("should handle deep nested attachment/detachment operations", () => {
    // Create a complex tree
    const root = mod.Tree_createNode(tree, "");
    const level1_1 = mod.Tree_createNode(
      tree,
      "",
    );
    const level1_2 = mod.Tree_createNode(
      tree,
      "",
    );
    const level2_1 = mod.Tree_createNode(
      tree,
      "",
    );
    const level2_2 = mod.Tree_createNode(
      tree,
      "",
    );
    const level3_1 = mod.Tree_createNode(
      tree,
      "",
    );

    // Build the tree structure
    mod.Tree_appendChild(tree, root, level1_1);
    mod.Tree_appendChild(tree, root, level1_2);
    mod.Tree_appendChild(
      tree,
      level1_1,
      level2_1,
    );
    mod.Tree_appendChild(
      tree,
      level1_2,
      level2_2,
    );
    mod.Tree_appendChild(
      tree,
      level2_1,
      level3_1,
    );

    // Check initial attachment state
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        level3_1,
      ),
    ).toBe(true);

    // Move a subtree
    mod.Tree_removeChild(
      tree,
      level1_1,
      level2_1,
    );
    mod.Tree_appendChild(
      tree,
      level1_2,
      level2_1,
    );

    // level3_1 should still be attached to root (through new path)
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        level3_1,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        level1_1,
        level3_1,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        level1_2,
        level3_1,
      ),
    ).toBe(true);

    // Detach at middle level
    mod.Tree_removeChild(
      tree,
      level1_2,
      level2_1,
    );

    // level3_1 should not be attached to root anymore
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        level3_1,
      ),
    ).toBe(false);
    // But the node should still exist
    expect(
      mod.Tree_doesNodeExist(tree, level3_1),
    ).toBe(true);

    // Reattach to root directly
    mod.Tree_appendChild(tree, root, level2_1);

    // level3_1 should be attached to root again
    expect(
      mod.Tree_getNodeContains(
        tree,
        root,
        level3_1,
      ),
    ).toBe(true);
  });

  it("should update attachment status when moving a node between parents", () => {
    // Create a structure with two separate parent nodes
    const root = mod.Tree_createNode(tree, "");
    const parent1 = mod.Tree_createNode(tree, "");
    const parent2 = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");

    // Attach both parents to root
    mod.Tree_appendChild(tree, root, parent1);
    mod.Tree_appendChild(tree, root, parent2);

    // Attach child to parent1
    mod.Tree_appendChild(tree, parent1, child);

    // Verify initial attachment
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent1,
        child,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent2,
        child,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeParent(tree, child),
    ).toBe(parent1);
    expect(
      mod.Tree_getChildrenCount(tree, parent1),
    ).toBe(1);
    expect(
      mod.Tree_getChildrenCount(tree, parent2),
    ).toBe(0);

    // Move child from parent1 to parent2
    mod.Tree_removeChild(tree, parent1, child);
    mod.Tree_appendChild(tree, parent2, child);

    // Verify updated attachment
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent1,
        child,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent2,
        child,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeParent(tree, child),
    ).toBe(parent2);
    expect(
      mod.Tree_getChildrenCount(tree, parent1),
    ).toBe(0);
    expect(
      mod.Tree_getChildrenCount(tree, parent2),
    ).toBe(1);

    // Child should still be attached to root through parent2
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(true);
  });

  it("should handle multiple reparenting operations correctly", () => {
    // Create a more complex structure
    const root = mod.Tree_createNode(tree, "");
    const branch1 = mod.Tree_createNode(tree, "");
    const branch2 = mod.Tree_createNode(tree, "");
    const leaf1 = mod.Tree_createNode(tree, "");
    const leaf2 = mod.Tree_createNode(tree, "");
    const leaf3 = mod.Tree_createNode(tree, "");

    // Set up initial structure
    mod.Tree_appendChild(tree, root, branch1);
    mod.Tree_appendChild(tree, root, branch2);
    mod.Tree_appendChild(tree, branch1, leaf1);
    mod.Tree_appendChild(tree, branch1, leaf2);
    mod.Tree_appendChild(tree, branch2, leaf3);

    // Verify initial state
    expect(
      mod.Tree_getChildrenCount(tree, branch1),
    ).toBe(2);
    expect(
      mod.Tree_getChildrenCount(tree, branch2),
    ).toBe(1);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf1,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf2,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        leaf3,
      ),
    ).toBe(true);

    // Perform multiple reparenting operations
    // Move leaf1 from branch1 to branch2
    mod.Tree_removeChild(tree, branch1, leaf1);
    mod.Tree_appendChild(tree, branch2, leaf1);

    // Move leaf3 from branch2 to branch1
    mod.Tree_removeChild(tree, branch2, leaf3);
    mod.Tree_appendChild(tree, branch1, leaf3);

    // Verify the updated structure
    expect(
      mod.Tree_getChildrenCount(tree, branch1),
    ).toBe(2);
    expect(
      mod.Tree_getChildrenCount(tree, branch2),
    ).toBe(1);

    // Check specific node attachments
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf1,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        leaf1,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf2,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf3,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        leaf3,
      ),
    ).toBe(false);

    // All leaves should still be attached to root
    expect(
      mod.Tree_getNodeContains(tree, root, leaf1),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf2),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf3),
    ).toBe(true);
  });

  it("should automatically detach node from previous parent when attached to a new parent", () => {
    // Create a structure with two separate parent nodes
    const root = mod.Tree_createNode(tree, "");
    const parent1 = mod.Tree_createNode(tree, "");
    const parent2 = mod.Tree_createNode(tree, "");
    const child = mod.Tree_createNode(tree, "");

    // Attach both parents to root
    mod.Tree_appendChild(tree, root, parent1);
    mod.Tree_appendChild(tree, root, parent2);

    // Attach child to parent1
    mod.Tree_appendChild(tree, parent1, child);

    // Verify initial attachment
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent1,
        child,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent2,
        child,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeParent(tree, child),
    ).toBe(parent1);
    expect(
      mod.Tree_getChildrenCount(tree, parent1),
    ).toBe(1);
    expect(
      mod.Tree_getChildrenCount(tree, parent2),
    ).toBe(0);

    // Now directly attach child to parent2 WITHOUT first removing it from parent1
    mod.Tree_appendChild(tree, parent2, child);

    // Verify child is automatically detached from parent1
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent1,
        child,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        parent2,
        child,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeParent(tree, child),
    ).toBe(parent2);
    expect(
      mod.Tree_getChildrenCount(tree, parent1),
    ).toBe(0);
    expect(
      mod.Tree_getChildrenCount(tree, parent2),
    ).toBe(1);

    // Child should still be attached to root through parent2
    expect(
      mod.Tree_getNodeContains(tree, root, child),
    ).toBe(true);
  });

  it("should automatically detach nodes in complex hierarchies", () => {
    // Create a hierarchical structure
    const root = mod.Tree_createNode(tree, "");
    const branch1 = mod.Tree_createNode(tree, "");
    const branch2 = mod.Tree_createNode(tree, "");
    const subbranch = mod.Tree_createNode(
      tree,
      "",
    );
    const leaf = mod.Tree_createNode(tree, "");

    // Build initial tree: root -> branch1 -> subbranch -> leaf
    mod.Tree_appendChild(tree, root, branch1);
    mod.Tree_appendChild(tree, root, branch2);
    mod.Tree_appendChild(
      tree,
      branch1,
      subbranch,
    );
    mod.Tree_appendChild(tree, subbranch, leaf);

    // Verify initial tree structure
    expect(
      mod.Tree_getNodeParent(tree, subbranch),
    ).toBe(branch1);
    expect(
      mod.Tree_getNodeParent(tree, leaf),
    ).toBe(subbranch);
    expect(
      mod.Tree_getChildrenCount(tree, branch1),
    ).toBe(1);
    expect(
      mod.Tree_getChildrenCount(tree, branch2),
    ).toBe(0);
    expect(
      mod.Tree_getChildrenCount(tree, subbranch),
    ).toBe(1);

    // Move subbranch (which contains leaf) directly to branch2
    mod.Tree_appendChild(
      tree,
      branch2,
      subbranch,
    );

    // Verify updated structure
    expect(
      mod.Tree_getNodeParent(tree, subbranch),
    ).toBe(branch2);
    expect(
      mod.Tree_getNodeParent(tree, leaf),
    ).toBe(subbranch);
    expect(
      mod.Tree_getChildrenCount(tree, branch1),
    ).toBe(0); // subbranch automatically removed
    expect(
      mod.Tree_getChildrenCount(tree, branch2),
    ).toBe(1);
    expect(
      mod.Tree_getChildrenCount(tree, subbranch),
    ).toBe(1); // leaf is still attached

    // Check that attachment paths are updated
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        subbranch,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch1,
        leaf,
      ),
    ).toBe(false);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        subbranch,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(
        tree,
        branch2,
        leaf,
      ),
    ).toBe(true);
    expect(
      mod.Tree_getNodeContains(tree, root, leaf),
    ).toBe(true); // Still attached to root through new path
  });
});

describe("Selection", () => {
  initTreeHook();
  it("should properly track selection", () => {
    // const root = mod.Tree_createNode(tree, "");
    const textNode = mod.Tree_createTextNode(
      tree,
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
    );
    console.log("tree_id", tree);
    // mod.Tree_appendChild(tree, root, textNode);
    mod.Tree_computeLayout(tree, "100", "100");
    const selection = mod.Tree_createSelection(
      tree,
      textNode,
      0,
      textNode,
      5,
    );
    // mod.Tree_dump(tree);
    mod.Selection_setFocus(
      tree,
      selection,
      textNode,
      10,
    );
    // // expect(mod.Tree_getSelectionStart(tree, selection)).toBe(0);
    // expect(mod.Tree_getSelectionEnd(tree, selection)).toBe(5);
  });
});
