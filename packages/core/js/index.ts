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
export type WasmLoader = ({
  dev,
}: {
  dev: boolean;
}) => Promise<Bytes>;
export type InitArgs = {
  logFn?: LogFn;
  readStream?: ReadStream;
  writeStream?: WriteStream;
  memory?: WebAssembly.Memory;
  dev?: boolean;
  loader: WasmLoader;
};

type Bytes =
  | Response
  | PromiseLike<Bytes>
  | ArrayBuffer
  | Uint8Array;

const _init = async (args: InitArgs) => {
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
    loader,
    readStream = process.stdin,
    writeStream = process.stdout,
    memory = new WebAssembly.Memory({
      initial: 1024,
    }),
  } = args;
  const eventSubscribers = new Set<
    (inputEvent: Uint32Array) => void
  >();
  // Events emitted during one wasm call are batched into a single deferred
  // flush: one dispatch task per burst instead of one per event. Without
  // this, each event's dispatch triggers its own render pass and fast
  // wheel streams build a backlog — scrolling keeps "momentum" after the
  // user stops because stale events are still draining.
  let pendingEvents: Uint32Array[] = [];
  let eventFlushScheduled = false;
  const bytes = await loader({
    dev:
      args.dev ??
      process.env.NODE_ENV === "development",
  });

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
      random_get: (ptr: number, len: number) => {
        const bytes = new Uint8Array(
          memory.buffer,
          ptr,
          len,
        );
        crypto.getRandomValues(bytes);
        return 0;
      },
      clock_res_get: notImplemented(
        "clock_res_get",
      ),
      poll_oneoff: notImplemented("poll_oneoff"),
      environ_sizes_get: (
        countPtr: number,
        sizePtr: number,
      ) => {
        const dataView = new DataView(
          memory.buffer,
        );
        dataView.setUint32(countPtr, 0, true);
        dataView.setUint32(sizePtr, 0, true);
        return 0;
      },
      environ_get: () => 0,
      fd_pwrite: notImplemented("fd_pwrite"),
      fd_pread: notImplemented("fd_pread"),
      fd_filestat_set_times: notImplemented(
        "fd_filestat_set_times",
      ),
      fd_filestat_set_size: notImplemented(
        "fd_filestat_set_size",
      ),
      fd_sync: notImplemented("fd_sync"),
      fd_seek: notImplemented("fd_seek"),
      fd_filestat_get: notImplemented(
        "fd_filestat_get",
      ),
      path_link: notImplemented("path_link"),
      path_symlink: notImplemented(
        "path_symlink",
      ),
      path_readlink: notImplemented(
        "path_readlink",
      ),
      path_rename: notImplemented("path_rename"),
      path_remove_directory: notImplemented(
        "path_remove_directory",
      ),
      path_unlink_file: notImplemented(
        "path_unlink_file",
      ),
      path_filestat_get: notImplemented(
        "path_filestat_get",
      ),
      fd_readdir: notImplemented("fd_readdir"),
      path_create_directory: notImplemented(
        "path_create_directory",
      ),
      clock_time_get: (
        _clockId: number,
        _precision: bigint,
        timePtr: number,
      ) => {
        const dataView = new DataView(
          memory.buffer,
        );
        dataView.setBigUint64(
          timePtr,
          BigInt(Math.round(Date.now() * 1e6)),
          true,
        );
        return 0;
      },
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

        // deferred: the wasm call that emitted this is still on the stack
        pendingEvents.push(data);
        if (!eventFlushScheduled) {
          eventFlushScheduled = true;
          setTimeout(() => {
            eventFlushScheduled = false;
            const batch = pendingEvents;
            pendingEvents = [];
            for (const event of batch) {
              for (const subscriber of eventSubscribers) {
                subscriber(event);
              }
            }
          }, 0);
        }
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
    isDev: args.dev ?? process.env.NODE_ENV === "development",
  };
};

export const init: typeof _init = memoize(_init);

export type Module = Awaited<
  ReturnType<typeof _init>
>;

export * from "./constants.js";
