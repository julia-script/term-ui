import * as stackTraceParser from "stacktrace-parser";
import * as v from "valibot";
// file: string | null;
// methodName: LiteralUnion<'<unknown>', string>;
// arguments: string[];
// lineNumber: number | null;
// column: number | null;
export const traceFrameSchema = v.object({
  file: v.nullable(v.string()),
  methodName: v.nullable(v.string()),
  arguments: v.array(v.string()),
  lineNumber: v.nullable(v.number()),
  column: v.nullable(v.number()),
  isTerm: v.boolean(),
});
export type TraceFrame = v.InferOutput<
  typeof traceFrameSchema
>;

export const traceSchema = v.object({
  message: v.string(),
  frames: v.array(traceFrameSchema),
});
export type Trace = v.InferOutput<
  typeof traceSchema
>;

export const parseTrace = (
  trace: string,
): v.InferOutput<typeof traceSchema> => {
  const lines = trace.split("\n");
  let message = "";

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line) continue;

    if (line.trimStart().startsWith("at ")) {
      break;
    }
    if (i > 0) {
      message += "\n";
    }
    message += line;
    i++;
  }
  const frames = stackTraceParser.parse(trace);

  return {
    message: trace,
    frames: frames.map((frame) => ({
      ...frame,
      methodName:
        frame.methodName === "<unknown>"
          ? null
          : frame.methodName,
      isTerm: !!frame.file?.includes("@termui/"),
    })),
  };
};
