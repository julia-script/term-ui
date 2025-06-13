import path from "node:path";
import {
  distDir,
  initFromFile,
} from "@term-ui/core/node";
import { Document } from "@term-ui/dom";
import type { ServerRouter } from "@termui/devtools/router/server";
import { createClient } from "@termui/devtools/rpc";
import { io } from "socket.io-client";

const client = createClient<ServerRouter>(
  io("http://localhost:9001"),
);

await client.waitForConnection();
await client.request("console", {
  level: "info",
  scope: "zig",
  args: ["Connected to server"],
  trace: {
    message: "",
    frames: [],
  },
});

try {
  const module = await initFromFile(undefined, {
    dev: true,

    logFn: (log) => {
      // client.request("console", {
      //   level: "log",
      //   scope: "zig",
      //   args: [log.message],
      //   trace: {
      //     message: "",
      //     frames: [],
      //   },
      // });
      // const result =  client.request("ping", "ping");
      // if (log.level === "error") {
      // console.error(log);
    },
  });

  const document = new Document(module, {
    onPaintRequest() {
      document.render();
    },
    size: {
      width: "100%",
      height: "100%",
    },
  });

  // // Set main container styles
  document.root.setStyle(`
  color: white; 
  border-style: rounded; 
  padding: 1;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  

`);

  const str =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";
  const text = document.createTextNode(str);
  const child = document.createElement("view");
  const caretResult =
    document.createTextNode("##");
  caretResult.setStyle(`
`);
  child.appendChild(text);
  document.root.appendChild(child);
  document.root.appendChild(caretResult);

  child.setStyle(`
  border-style: double; 
  text-align: center;
  width: 30;
  border-color: white;
  cursor: pointer;
  background-color: cyan;
`);

  child.addEventListener("mousemove", (e) => {
    client.request("console", {
      level: "log",
      scope: "example",
      args: [e.type, e.clientX, e.clientY],
      trace: {
        message: "",
        frames: [],
      },
    });
  });

  // const button = document.createElement("view");
  // const buttonText = document.createTextNode("Click me");
  // button.appendChild(text);
  // document.root.appendChild(button);
  // document.root.appendChild(buttonText);

  // button.setStyle(`
  //   border-style: double;
  //   text-align: center;
  //   width: 30;
  //   border-color: white;
  //   cursor: pointer;
  // `);
  // button.setText("Click me");

  // let timeout: number;
  // button.addEventListener("click", () => {
  //   clearTimeout(timeout);
  //   buttonText.setText("Thank you! 🎉");
  //   timeout = setTimeout(() => {
  //     buttonText.setText("Click me");
  //   }, 3000);
  // })

  //   document.render();
  //   document.selection?.extendBy(
  //     "character",
  //     "forward",
  //   );
  //   timeout = setTimeout(() => {
  //     button.setText("Click me");
  //     document.render(true);
  //   }, 3000);
  // });

  // // document.root.addEventListener("click", (e) => {
  // //   const bp = document.caretPositionFromPoint(
  // //     e.x,
  // //     e.y,
  // //   );
  // //   if (bp) {
  // //     // bpNode.setText(JSON.stringify(bp));
  // //     document.render(true);
  // //   }
  // // });
  // // document.root.addEventListener(
  // //   "mousedown",
  // //   (e) =>
  // //     const bp = document.caretPositionFromPoint(
  // //       e.x,
  // //       e.y,
  // //     );
  // //     if (!bp) return;
  // //     document.createSelection(bp);
  // //     bpNode.setText(JSON.stringify(bp));
  // //     document.render(true);
  // //   },
  // // );
  // let pressed = false;
  // const updateBpNode = () => {
  //   const selection = document.selection;

  //   const anchor = selection?.getAnchor();
  //   const focus = selection?.getFocus();
  //   const str = `[${anchor?.node ?? "null"}~${anchor?.offset ?? "null"}] [${focus?.node ?? "null"}~${focus?.offset ?? "null"}]`;
  //   bpNode.setText(str);
  //   document.render(true);
  // };
  // document.inputManager?.subscribe((e) => {
  //   if (e.kind !== "mouse") return;
  //   if (e.action === "press") {
  //     pressed = true;
  //     const bp = document.caretPositionFromPoint(
  //       e.x,
  //       e.y,
  //     );
  //     if (!bp) return;
  //     // console.log("bp", bp);
  //     document.createSelection(bp);
  //     document.render(true);

  //     // updateBpNode();
  //     updateBpNode();
  //   }
  //   if (e.action === "motion") {
  //     if (!pressed) return;
  //     const selection = document.selection;
  //     if (!selection) return;

  //     const bp = document.caretPositionFromPoint(
  //       e.x,
  //       e.y,
  //     );
  //     if (!bp) return;
  //     selection.setFocus(bp.node, bp.offset);
  //     updateBpNode();
  //     // updateBpNode();
  //   }
  //   if (e.action === "release") {
  //     pressed = false;
  //   }
  // });

  document.render();

  // button.addEventListener("mouse-enter", () => {
  //   button.setStyleProperty(
  //     "border-color",
  //     "radial-gradient(circle, cyan, magenta)",
  //   );
  //   document.render(true);
  // });

  // button.addEventListener("mouse-leave", () => {
  //   button.setStyleProperty(
  //     "border-color",
  //     "white",
  //   );
  //   document.render(true);
  // });
} catch (error) {
  // client.request("console", {
  //   level: "error",
  //   scope: "zig",
  //   args: [error.message],
  //   trace: {
  //     message: "",
  //     frames: [],
  //   },
  // });
}
