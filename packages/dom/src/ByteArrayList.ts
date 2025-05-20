import type { Module } from "@term-ui/core";
const encoder = new TextEncoder();

export class ByteArrayList {
  ptr: number;
  isDisposed = false;
  constructor(public module: Module) {
    this.ptr = module.ArrayList_init();
  }
  assertNotDisposed() {
    if (this.isDisposed) {
      throw new Error(
        "ByteArrayList is disposed",
      );
    }
  }

  dispose() {
    // debug.log("dispose ByteArrayList");
    this.assertNotDisposed();
    this.module.ArrayList_deinit(this.ptr);
    this.isDisposed = true;
  }
  [Symbol.dispose]() {
    this.dispose();
  }
  get length() {
    return this.module.ArrayList_getLength(
      this.ptr,
    );
  }
  set length(length: number) {
    this.module.ArrayList_setLength(
      this.ptr,
      length,
    );
  }

  get slicePtr() {
    return this.module.ArrayList_getPointer(
      this.ptr,
    );
  }

  appendSlice(slice: ArrayLike<number>) {
    this.assertNotDisposed();
    const ptr = this.module.ArrayList_appendUnusedSlice(
      this.ptr,
      slice.length,
    );
    const buffer = new Uint8Array(
      this.module.memory.buffer,
      ptr,
      slice.length,
    );
    buffer.set(slice);
  }
  appendString(string: string) {
    this.assertNotDisposed();
    const slice = encoder.encode(string);

    this.appendSlice(slice);
  }
}
