import { dirname } from "node:path";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { initFromFile } from "./node";

const mod = await initFromFile(
  path.join(
    dirname(fileURLToPath(import.meta.url)),
    "../dist/core.wasm",
  ),
  {},
);

const tree = mod.Tree_init();
const renderer = mod.Renderer_init();

const root = mod.Tree_createNode(
  tree,
  `
display: flex;
width: 100%; 
height: 100%; 
background-color: red;
`,
);

const button = mod.Tree_createNode(
  tree,
  `
background-color: blue; 
color: white; 
text-align: center;
width: 20;
margin: auto;
`,
);

const buttonText = mod.Tree_createTextNode(
  tree,
  "Click me",
);
mod.Tree_appendChild(tree, button, buttonText);
mod.Tree_appendChild(tree, root, button);
// mod.Tree_setElementId(tree, button, "my-button");

mod.Tree_computeStyles(tree);
mod.Tree_buildLayoutTree(tree);
mod.Tree_computeLayout(tree, "40", "20");

mod.Tree_paintSimple(tree, renderer);

console.log("Layout tree:");
mod.Tree_dump(tree);
mod.Tree_dumpLayoutTree(tree);
mod.Renderer_deinit(renderer);
mod.Tree_deinit(tree);
if (mod.detectLeaks()) {
  console.log("Leaks detected");
} else {
  console.log("No leaks detected");
}
