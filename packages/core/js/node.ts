import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { memoize } from "lodash-es";
import {
  type InitArgs,
  type WasmLoader,
  init,
} from "./index.js";

export type { Module } from "./index.js";

export const distDir = join(
  dirname(fileURLToPath(import.meta.url)),
);

const _initFromFile = async (
  path?: string,
  args: Omit<InitArgs, "loader"> = {},
) => {
  // Use dev flag from args, defaulting to NODE_ENV check
  const isDev =
    args.dev ??
    process.env.NODE_ENV === "development";

  if (!path) {
    const wasmFile = isDev
      ? "core-debug.wasm"
      : "core.wasm";
    path = join(distDir, wasmFile);
  }

  const bytes = await readFile(path);
  return await init({
    ...args,
    loader: async () => new Uint8Array(bytes),
  });
};

export const initFromFile: typeof _initFromFile =
  memoize(_initFromFile);

export const loader: WasmLoader = async ({
  dev,
}) => {
  const wasmFile = dev
    ? "core-debug.wasm"
    : "core.wasm";
  const bytes = await readFile(
    join(distDir, wasmFile),
  );
  return new Uint8Array(bytes);
};
