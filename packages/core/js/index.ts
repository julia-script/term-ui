import { decode } from "@term-ui/shared/string";
import type {
  ReadStream,
  WriteStream,
} from "@term-ui/shared/types";
import memoize from "lodash-es/memoize";
import { instance, parse } from "valibot";
import { getSchema } from "./exportsSchema.js";

const notImplemented =
  (name: string) =>
  (...args: unknown[]) => {
    console.log(
      `tried to call ${name} with:`,
      args,
    );
    throw new Error(`${name} not implemented`);
  };

const instantiate = async (
  bytes:
    | Response
    | PromiseLike<Response>
    | ArrayBuffer
    | Uint8Array,
  importObject: WebAssembly.Imports,
) => {
  if (
    bytes instanceof Response ||
    bytes instanceof Promise
  ) {
    const { instance, module } =
      await WebAssembly.instantiateStreaming(
        bytes,
        importObject,
      );
    return instance;
  }
  const instance = await WebAssembly.instantiate(
    bytes,
    importObject,
  );

  // @ts-expect-error
  return instance.instance;
};
export type Log = {
  dt: number;
  pid: number;
  level: string;
  scope: string;
  message: string;
};
export type LogFn = (log: Log) => void;
export type InitArgs = {
  logFn?: LogFn;
  readStream?: ReadStream;
  writeStream?: WriteStream;
  memory?: WebAssembly.Memory;
  dev?: boolean;
};
const _init = async (
  bytes:
    | Response
    | PromiseLike<Response>
    | ArrayBuffer
    | Uint8Array,
  args: InitArgs = {},
) => {
  // readStream: ReadStream = process.stdin,
  // writeStream: WriteStream = process.stdout,
  // memory: WebAssembly.Memory = new WebAssembly.Memory(
  //   {
  //     // initial: 512,
  //     initial: 1024,
  //   },
  // ),
  const {
    logFn = (log: Log) => {
      console.log(log);
    },
    readStream = process.stdin,
    writeStream = process.stdout,
    memory = new WebAssembly.Memory({
      initial: 1024,
    }),
  } = args;
  const eventSubscribers = new Set<
    (inputEvent: Uint32Array) => void
  >();

  const module = await instantiate(bytes, {
    wasi_snapshot_preview1: {
      fd_write: (
        fd: number,
        iovsPtr: number,
        iovsLength: number,
        bytesWrittenPtr: number,
      ) => {
        const iovs = new Uint32Array(
          memory.buffer,
          iovsPtr,
          iovsLength * 2,
        );
        const stdout = 1;
        const stderr = 2;

        let totalBytesWritten = 0;
        for (
          let i = 0;
          i < iovsLength * 2;
          i += 2
        ) {
          const offset = iovs[i];
          const length = iovs[i + 1] ?? 0;
          switch (fd) {
            case stdout:
              writeStream.write(
                new Uint8Array(
                  memory.buffer,
                  offset,
                  length,
                ),
              );
              break;
            case stderr:
              // process.stderr.write(
              //   new Uint8Array(
              //     memory.buffer,
              //     offset,
              //     length,
              //   ),
              // );
              writeStream.write(
                decode(
                  new Uint8Array(
                    memory.buffer,
                    offset,
                    length,
                  ),
                ),
              );
              break;
            default:
              throw new Error(
                "Invalid file descriptor",
              );
          }

          totalBytesWritten += length;
          const dataView = new DataView(
            memory.buffer,
          );
          dataView.setInt32(
            bytesWrittenPtr,
            totalBytesWritten,
            true,
          );
        }
        return 0;
      },

      args_get: notImplemented("args_get"),
      args_sizes_get: notImplemented(
        "args_sizes_get",
      ),
      fd_close: notImplemented("fd_close"),
      fd_fdstat_get: notImplemented(
        "fd_fdstat_get",
      ),
      fd_prestat_get: notImplemented(
        "fd_prestat_get",
      ),
      fd_read: notImplemented("fd_read"),
      fd_prestat_dir_name: notImplemented(
        "fd_prestat_dir_name",
      ),
      path_open: notImplemented("path_open"),
      proc_exit: notImplemented("proc_exit"),
      random_get: notImplemented("random_get"),
    },
    env: {
      memory: memory,
      externalLog: (ptr: number) => {
        const dt = Date.now();
        const pid = process.pid;
        // console.log("externalLog", ptr);
        const view = new Uint8Array(
          memory.buffer,
          ptr,
        );
        const end = view.indexOf(0);
        const message = view.slice(0, end);
        const string = decode(message);
        // exports.freeNullTerminatedBuffer(ptr);
        const headerEnd = string.indexOf("\r\n");
        const header = string.slice(0, headerEnd);
        const content = string.slice(
          headerEnd + 2,
        );
        const parsedHeader: Record<
          string,
          string
        > = Object.fromEntries(
          header.split(";").flatMap((item) => {
            if (item.length === 0) return [];
            const [key = "", value = ""] =
              item.split(":");
            return [[key.trim(), value.trim()]];
          }),
        );

        logFn?.({
          dt,
          pid,
          level: parsedHeader.level ?? "",
          scope: parsedHeader.scope ?? "",
          message: content,
        });
      },
      emitEvent: (ptr: number) => {
        const data = new Uint32Array(8);
        data.set(
          new Uint32Array(
            memory.buffer,

            ptr,
            8,
          ),
        );

        // ensure the event is only called after the current call stack is cleared
        // TODO: check if queueMicrotask would do the job
        setTimeout(() => {
          for (const subscriber of eventSubscribers) {
            subscriber(data);
          }
        }, 0);
      },
      // diplomat_console_error_js: notImplemented(
      //   "diplomat_console_error_js",
      // ),
      // diplomat_console_warn_js: notImplemented(
      //   "diplomat_console_warn_js",
      // ),
      // diplomat_console_info_js: notImplemented(
      //   "diplomat_console_info_js",
      // ),
      // diplomat_console_log_js: notImplemented(
      //   "diplomat_console_log_js",
      // ),
      // diplomat_console_debug_js: notImplemented(
      //   "diplomat_console_debug_js",
      // ),
    },
  });

  const exports = parse(
    getSchema(memory, module.exports, logFn),
    module.exports,
  );
  return {
    ...exports,
    log: (...args: unknown[]) => {
      logFn({
        dt: Date.now(),
        pid: process.pid,
        level: "log",
        scope: "zig",
        message: JSON.stringify(args),
      });
    },
    subscribe: (
      subscriber: (
        inputEvent: Uint32Array,
      ) => void,
    ) => {
      eventSubscribers.add(subscriber);
      return () => {
        eventSubscribers.delete(subscriber);
      };
    },
    module,
    memory,
  };
};

export const init: typeof _init = memoize(_init);

export type Module = Awaited<
  ReturnType<typeof _init>
>;

export * from "./constants.js";
