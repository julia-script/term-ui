import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
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
    logFn: console.log,
  },
);

let tree: number;
let renderer: number;

const initTestHook = () =>
  beforeEach(async () => {
    tree = mod.Tree_init();
    renderer = mod.Renderer_init();
    return () => {
      mod.Renderer_deinit(renderer);
      mod.Tree_deinit(tree);
      expect(mod.detectLeaks()).toBe(false);
    };
  });

describe("Rendering System Tests", () => {
  initTestHook();

  it("should render a simple button to the screen", () => {
    // Create a button element
    const button = mod.Tree_createNode(tree, 
      "display: block; width: 100px; height: 30px; background-color: blue; color: white; text-align: center;"
    );
    const buttonText = mod.Tree_createTextNode(tree, "Click Me");
    
    // Build the DOM structure
    mod.Tree_appendChild(tree, button, buttonText);
    
    // Set element ID for testing
    mod.Tree_setElementId(tree, button, "my-button");
    
    // Compute layout
    mod.Tree_computeLayout(tree, "400", "300");
    
    // Test getElementById
    const foundButton = mod.Tree_getElementById(tree, "my-button");
    expect(foundButton).toBe(button);
    
    // Test hit testing on the button
    const hitResult = mod.Tree_hitTest(tree, 50, 15); // Center of button
    expect(hitResult).toBe(button);
    
    // Test caret positioning in text
    const caretPos = mod.Tree_caretPositionFromPoint(tree, 45, 15);
    expect(caretPos).not.toBe(null);
    expect(caretPos?.node).toBe(buttonText);
    
    // Render to stdout (this will actually output to console)
    console.log("\\n=== Rendering Button ===");
    mod.Renderer_renderToStdout(renderer, tree, true);
    console.log("=== End Rendering ===\\n");
    
    // Test invalidation status
    const invalidationStatus = mod.Tree_getNodeInvalidationStatus(tree, button);
    console.log(`Button invalidation status: ${invalidationStatus}`);
  });

  it("should render a complex layout with multiple elements", () => {
    // Create container
    const container = mod.Tree_createNode(tree,
      "display: block; width: 300px; height: 200px; padding: 20px; background-color: gray;"
    );
    
    // Create header
    const header = mod.Tree_createNode(tree,
      "display: block; width: 100%; height: 40px; background-color: darkblue; color: white; text-align: center;"
    );
    const headerText = mod.Tree_createTextNode(tree, "Header Title");
    mod.Tree_appendChild(tree, header, headerText);
    
    // Create content area
    const content = mod.Tree_createNode(tree,
      "display: block; width: 100%; height: 100px; margin-top: 10px; background-color: white; padding: 10px;"
    );
    const contentText = mod.Tree_createTextNode(tree, "This is some content text that should wrap nicely within the container.");
    mod.Tree_appendChild(tree, content, contentText);
    
    // Create button
    const button = mod.Tree_createNode(tree,
      "display: block; width: 80px; height: 30px; margin-top: 10px; background-color: green; color: white; text-align: center;"
    );
    const buttonText = mod.Tree_createTextNode(tree, "Submit");
    mod.Tree_appendChild(tree, button, buttonText);
    
    // Build the structure
    mod.Tree_appendChild(tree, container, header);
    mod.Tree_appendChild(tree, container, content);
    mod.Tree_appendChild(tree, container, button);
    
    // Set IDs for testing
    mod.Tree_setElementId(tree, container, "container");
    mod.Tree_setElementId(tree, header, "header");
    mod.Tree_setElementId(tree, content, "content");
    mod.Tree_setElementId(tree, button, "submit-btn");
    
    // Compute layout
    mod.Tree_computeLayout(tree, "400", "300");
    
    // Test all elements can be found by ID
    expect(mod.Tree_getElementById(tree, "container")).toBe(container);
    expect(mod.Tree_getElementById(tree, "header")).toBe(header);
    expect(mod.Tree_getElementById(tree, "content")).toBe(content);
    expect(mod.Tree_getElementById(tree, "submit-btn")).toBe(button);
    
    // Test hit testing on different elements
    const hitHeader = mod.Tree_hitTest(tree, 150, 40);
    const hitContent = mod.Tree_hitTest(tree, 150, 100);
    const hitButton = mod.Tree_hitTest(tree, 60, 180);
    
    console.log(`Hit results - Header: ${hitHeader}, Content: ${hitContent}, Button: ${hitButton}`);
    
    // Test that we can get node at position with renderer
    const nodeAtButton = mod.Renderer_getNodeAt(renderer, tree, 60, 180);
    expect(nodeAtButton).toBe(button);
    
    // Render the complete layout
    console.log("\\n=== Rendering Complex Layout ===");
    mod.Renderer_renderToStdout(renderer, tree, true);
    console.log("=== End Rendering ===\\n");
  });

  it("should handle style property updates with proper invalidation", () => {
    // Create a test element
    const element = mod.Tree_createNode(tree, "display: block; width: 100px; height: 50px;");
    const text = mod.Tree_createTextNode(tree, "Test Element");
    mod.Tree_appendChild(tree, element, text);
    
    // Initial layout
    mod.Tree_computeLayout(tree, "400", "300");
    
    // Test individual property updates
    mod.Tree_setStyleProperty(tree, element, "background-color", "red");
    mod.Tree_setStyleProperty(tree, element, "width", "150px");
    mod.Tree_setStyleProperty(tree, element, "color", "white");
    
    // Check invalidation status after changes
    const status = mod.Tree_getNodeInvalidationStatus(tree, element);
    console.log(`Invalidation status after style changes: ${status}`);
    
    // Recompute layout to apply changes
    mod.Tree_computeLayout(tree, "400", "300");
    
    // Render updated element
    console.log("\\n=== Rendering Updated Element ===");
    mod.Renderer_renderToStdout(renderer, tree, true);
    console.log("=== End Rendering ===\\n");
  });

  it("should test caret positioning and text interaction", () => {
    // Create a text container with multiple lines
    const textContainer = mod.Tree_createNode(tree,
      "display: block; width: 200px; padding: 10px; background-color: lightyellow;"
    );
    
    const paragraph1 = mod.Tree_createTextNode(tree, "First paragraph of text. ");
    const paragraph2 = mod.Tree_createTextNode(tree, "Second paragraph with more content.");
    
    mod.Tree_appendChild(tree, textContainer, paragraph1);
    mod.Tree_appendChild(tree, textContainer, paragraph2);
    
    // Compute layout
    mod.Tree_computeLayout(tree, "400", "300");
    
    // Test caret positioning at different points
    const caretStart = mod.Tree_caretPositionFromPoint(tree, 15, 15);
    const caretMiddle = mod.Tree_caretPositionFromPoint(tree, 100, 25);
    const caretEnd = mod.Tree_caretPositionFromPoint(tree, 180, 35);
    
    console.log("Caret positions:");
    console.log(`Start: node=${caretStart?.node}, offset=${caretStart?.offset}`);
    console.log(`Middle: node=${caretMiddle?.node}, offset=${caretMiddle?.offset}`);
    console.log(`End: node=${caretEnd?.node}, offset=${caretEnd?.offset}`);
    
    // Test that caret positioning returns valid positions
    expect(caretStart).not.toBe(null);
    expect(caretMiddle).not.toBe(null);
    expect(caretEnd).not.toBe(null);
    
    // Render the text container
    console.log("\\n=== Rendering Text Container ===");
    mod.Renderer_renderToStdout(renderer, tree, true);
    console.log("=== End Rendering ===\\n");
  });
});