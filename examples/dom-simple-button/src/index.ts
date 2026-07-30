// import path from "node:path";
// import { io } from "socket.io-client";
import { loader } from "@term-ui/core/node";
import { init } from "@term-ui/core";
// import {}
import { Document } from "@term-ui/dom";

// const client = createClient<ServerRouter>(
//   io("http://localhost:9001"),
// );

// process.stderr.write = (...args) => {
//   client.request("console", {
//     level: "log",
//     scope: "log",
//     args: args,
//     trace: {
//       message: "",
//       frames: [],
//     },
//   });
// };
// console.log = (...args) => {
//   client.request("console", {
//     level: "log",
//     scope: "log",
//     args: args,
//     trace: {
//       message: "",
//       frames: [],
//     },
//   });
// };
// await client.waitForConnection();
// await client.request("console", {
//   level: "info",
//   scope: "zig",
//   args: ["Connected to server"],
//   trace: {
//     message: "",
//     frames: [],
//   },
// });

try {
  const module = await init({
    dev: true,
    loader,
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
  const render = () => {
    document.render();
  };
  const document = new Document(module, {
    onPaintRequest() {
      // render
      // console.log(
      //   "clientHeight",
      //   child.clientHeight,
      //   "scrollHeight",
      //   child.scrollHeight,
      //   "scrollTop",
      //   child.scrollTop,
      //   "scrollTopMax",
      //   child.scrollTopMax,
      // );
    },
    size: {
      width: "100%",
      height: "100%",
    },
  });

  // // Set main container styles
  document.root.setStyle(`
  color: white; 
  // border-style: rounded; 
  // padding: 1;
  // width: 100%;
  // height: 100%;
  // display: flex;
  // flex-direction: column;
  // align-items: center;
  // justify-content: center;
  // background-color: black;
  // white-space: pre-wrap;
  // overflow-y: scroll;

  
`);

  // const str =
  //   "When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon. There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow";
  // // const str =
  //   "The quick brown fox jumps over the lazy dog";
  // const text = document.createTextNode(str);
  const child = document.createElement("view");
  // child.appendChild(text);

  document.root.appendChild(child);

  // child.addEventListener("wheel", (e) => {
  //   console.log("wheel", "child", e.deltaY);
  //   // e.preventDefault();
  // });
  // child.addEventListener("mousedown", (e) => {
  //   console.log(
  //     "mousedown",
  //     "child",
  //     e.clientX,
  //     e.clientY,
  //   );
  // });
  // child.addEventListener("mouseup", (e) => {
  //   console.log(
  //     "mouseup",
  //     "child",
  //     e.clientX,
  //     e.clientY,
  //   );
  // });
  setInterval(() => {
    const el = document.createTextNode(
      'X'
    );
    child.appendChild(el);
    document.render()
  }, 1000);
  child.addEventListener("wheel", (e) => {
    // console.log(child.id, child.clientHeight);

    document.render();
  });
  // child.addEventListener("scroll", (e) => {
  //   console.log("scroll", "child", child.scrollTop);
  // });

  // document.tree.dump();
  child.setStyle(`
  border-style: double; 
  // text-align: center;
  width: 30;
  height: 5;
  // border-color: white;
  // cursor: pointer;
  background-color: cyan;
  // white-space: pre-wrap;
  overflow: scroll;
    overflow-y: scroll;
`);

  document.render();
} catch (error) {
  console.error(error);
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
