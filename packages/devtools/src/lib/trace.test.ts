import * as stackTraceParser from "stacktrace-parser";
import { describe, expect, it } from "vitest";
import { parseTrace } from "./trace";

const nodeTrace = [
  `Error: Something went wrong
    at file:///Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:1:13
    at ModuleJob.run (node:internal/modules/esm/module_job:274:25)
    at async onImport.tracePromise.__proto__ (node:internal/modules/esm/loader:644:26)
    at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:98:5)`,
  `ValiError: Invalid type: Expected string but received 2
    at Module.parse (file:///Users/juliaortiz/Documents/dev.nosync/cpp/node_modules/.pnpm/valibot@1.0.0_typescript@5.8.3/node_modules/valibot/dist/index.js:6593:11)
    at file:///Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:4:5
    at ModuleJob.run (node:internal/modules/esm/module_job:274:25)
    at async onImport.tracePromise.__proto__ (node:internal/modules/esm/loader:644:26)
    at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:98:5)`,
];
const bunTrace = [
  `Error: Something went wrong
    at /Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:1:17
    at moduleEvaluation (native:1:11)
    at moduleEvaluation (native:1:11)
    at loadAndEvaluateModule (native:2)`,

  `ValiError: Invalid type: Expected string but received 2
    at new ValiError (/Users/juliaortiz/Documents/dev.nosync/cpp/node_modules/.pnpm/valibot@1.0.0_typescript@5.8.3/node_modules/valibot/dist/index.js:271:5)
    at parse (/Users/juliaortiz/Documents/dev.nosync/cpp/node_modules/.pnpm/valibot@1.0.0_typescript@5.8.3/node_modules/valibot/dist/index.js:6593:15)
    at /Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:4:5
    at moduleEvaluation (native:1:11)
    at moduleEvaluation (native:1:11)
    at loadAndEvaluateModule (native:2)`,
];

const denoTrace = [
  `Error: Something went wrong
    at file:///Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:1:13`,
  `ValiError: Invalid type: Expected string but received 2
    at Module.parse (file:///Users/juliaortiz/Documents/dev.nosync/cpp/node_modules/.pnpm/valibot@1.0.0_typescript@5.8.3/node_modules/valibot/dist/index.js:6593:11)
    at file:///Users/juliaortiz/Documents/dev.nosync/cpp/packages/devtools/trace.js:4:5`,
];

describe("parseTrace", () => {
  it("should parse a trace", () => {
    const traces = [
      ...nodeTrace,
      ...bunTrace,
      ...denoTrace,
    ];
    for (const trace of traces) {
      // const parsed = parseTrace(trace);
      const stack = stackTraceParser.parse(trace);
      const parsed = parseTrace(trace);
      console.log(parsed);
      // console.log(stack);
    }
    // const trace = "Error: test";
    // const parsed = parseTrace(trace);
    // expect(parsed).toEqual({ message: trace, frames: [] });
  });
});
