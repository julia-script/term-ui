import { uniq, uniqueId } from "lodash-es";
import {
  type InferOutput,
  args,
  boolean,
  function_,
  instance,
  literal,
  number,
  object,
  optional,
  pipe,
  returns,
  string,
  transform,
  tuple,
  union,
  unknown,
  void_,
} from "valibot";
import type { LogFn } from "./index.ts";
const encoder = new TextEncoder();

export const getSchema = (
  memory: WebAssembly.Memory,
  _instance: unknown,
  logFn: LogFn,
) => {
  const module = _instance as InferOutput<
    ReturnType<typeof getSchema>
  >;
  const catchError = <
    // biome-ignore lint/suspicious/noExplicitAny:
    T extends (...args: any[]) => any,
  >(
    name: string,
  ) =>
    transform<T, T>((fn: T) => {
      const callId = uniqueId("call_");
      return ((...args) => {
        try {
          // const trace = new Error().stack;
          // logFn({
          //   dt: Date.now(),
          //   pid: process.pid,
          //   level: "lifecycle",
          //   scope: name,
          //   message: `${callId} ${name}\n${trace}`,
          // });
          return fn(...args);
        } catch (e) {
          logFn({
            dt: Date.now(),
            pid: process.pid,
            level: "lifecycle",
            scope: name,
            message: `${callId} ${name} failed`,
          });
          throw e;
        }
      }) as T;
    });
  const booleanish = pipe(
    unknown(),
    transform((b) => !!b),
  );

  const zigString = pipe(
    string(),
    transform((str): number => {
      const buffer = encoder.encode(str);
      const bufferPtr =
        module.allocNullTerminatedBuffer(
          buffer.length,
        );
      const bufferArray = new Uint8Array(
        memory.buffer,
        bufferPtr,
        buffer.length,
      );
      bufferArray.set(buffer);
      return bufferPtr;
    }),
  );
  const zigBuffer = pipe(
    union([
      instance(ArrayBuffer),
      instance(Uint8Array),
    ]),
    transform((buffer): number => {
      const normalized =
        buffer instanceof Uint8Array
          ? buffer
          : new Uint8Array(buffer);

      const bufferPtr = module.allocBuffer(
        normalized.byteLength +
          Uint32Array.BYTES_PER_ELEMENT,
      );
      const bufferArray = new Uint8Array(
        memory.buffer,
        bufferPtr + Uint32Array.BYTES_PER_ELEMENT,
        normalized.byteLength,
      );
      const dataView = new DataView(
        memory.buffer,
      );
      dataView.setUint32(
        bufferPtr,
        normalized.byteLength,
        true,
      );

      bufferArray.set(normalized);
      return bufferPtr;
    }),
  );

  const NULL = 4294967295;
  const boundaryPointSchema = pipe(
    number(),
    transform(
      (
        ptr,
      ): {
        node: number;
        offset: number;
      } | null => {
        const array = new Uint32Array(
          memory.buffer,
          ptr,
          2,
        );
        if (array[0] === NULL) {
          return null;
        }
        return {
          node: array[0] as number,
          offset: array[1] as number,
        };
      },
    ),
  );

  return object({
    // NULL: pipe(
    //   instance(WebAssembly.Global),
    //   transform((ptr) => {
    //     const array = new Uint32Array(
    //       memory.buffer,
    //       ptr.value,
    //       1,
    //     );
    //     const value = array[0];
    //     console.log("array", value);
    //     return value;
    //   }),
    // ),
    Tree_init: pipe(
      function_(),
      args(tuple([])),
      returns(number()),
      catchError("Tree_init"),
    ),
    Tree_deinit: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_deinit"),
    ),
    Tree_createNode: pipe(
      function_(),
      args(tuple([number(), zigString])),
      returns(number()),
      catchError("Tree_createNode"),
    ),
    Tree_getNodeParent: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Tree_getNodeParent"),
    ),
    Tree_createTextNode: pipe(
      function_(),
      args(tuple([number(), zigString])),
      returns(number()),
      catchError("Tree_createTextNode"),
    ),
    Tree_doesNodeExist: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(booleanish),
      catchError("Tree_doesNodeExist"),
    ),
    Tree_getNodeContains: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(booleanish),
      catchError("Tree_getNodeContains"),
    ),

    Tree_appendChild: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(number()),
      catchError("Tree_appendChild"),
    ),

    Tree_insertBefore: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(number()),
      catchError("Tree_insertBefore"),
    ),

    Tree_removeChild: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(void_()),
      catchError("Tree_removeChild"),
    ),

    Tree_removeChildren: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_removeChildren"),
    ),

    Tree_getChildrenCount: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Tree_getChildrenCount"),
    ),

    Tree_getNodeKind: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Tree_getNodeKind"),
    ),

    Tree_appendChildAtIndex: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(number()),
      catchError("Tree_appendChildAtIndex"),
    ),

    Tree_getChildren: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            // reply-arena buffer: [u32 count][ids]; copy immediately
            const view = new DataView(
              memory.buffer,
            );
            const count = view.getUint32(
              ptr,
              true,
            );
            const ids = new Uint32Array(
              memory.buffer,
              ptr + 4,
              count,
            );
            return Array.from(ids);
          }),
        ),
      ),
      catchError("Tree_getChildren"),
    ),

    Tree_setStyle: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(void_()),
      catchError("Tree_setStyle"),
    ),

    Tree_setStyleProperty: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          zigString,
          zigString,
        ]),
      ),
      returns(void_()),
      catchError("Tree_setStyleProperty"),
    ),

    Tree_destroyNode: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_destroyNode"),
    ),

    Tree_destroyNodeRecursive: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_destroyNodeRecursive"),
    ),
    Tree_getNodeCursorStyle: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Tree_getNodeCursorStyle"),
    ),
    Tree_dump: pipe(
      function_(),
      args(tuple([number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            const array = new Uint8Array(
              memory.buffer,
              ptr,
            );
            let end = 0;
            while (array[end] !== 0) {
              end++;
            }
            
            return new TextDecoder().decode(array.slice(0, end));
          }),
        ),
      ),
      catchError("Tree_dump"),
    ),
    Tree_dumpLayoutTree: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_dumpLayoutTree"),
    ),

    Node_setText: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(void_()),
      catchError("Node_setText"),
    ),
    Node_getText: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            // reply-arena buffer: [u32 len][utf8 bytes]; copy immediately
            const view = new DataView(
              memory.buffer,
            );
            const len = view.getUint32(
              ptr,
              true,
            );
            const bytes = new Uint8Array(
              memory.buffer,
              ptr + 4,
              len,
            );
            return new TextDecoder().decode(
              bytes,
            );
          }),
        ),
      ),
      catchError("Node_getText"),
    ),
    Node_getTextLength: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getTextLength"),
    ),
    Node_appendData: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(void_()),
      catchError("Node_appendData"),
    ),
    Node_insertData: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          zigString,
        ]),
      ),
      returns(void_()),
      catchError("Node_insertData"),
    ),
    Node_replaceData: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
          zigString,
        ]),
      ),
      returns(void_()),
      catchError("Node_replaceData"),
    ),
    Node_deleteData: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(void_()),
      catchError("Node_deleteData"),
    ),
    Node_isEditingHost: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(booleanish),
      catchError("Node_isEditingHost"),
    ),
    Node_isEditable: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(booleanish),
      catchError("Node_isEditable"),
    ),
    Node_getEditingHost: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getEditingHost"),
    ),
    Node_inSameEditingHost: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(booleanish),
      catchError("Node_inSameEditingHost"),
    ),
    Node_compareDocumentPosition: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(number()),
      catchError("Node_compareDocumentPosition"),
    ),
    Node_getClientRects: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            // Read f32 array with format: [flag, x, y, width, height, ...]
            // flag is 1.0 for valid rect, 0.0 for end
            const rects: Array<{
              x: number;
              y: number;
              width: number;
              height: number;
            }> = [];
            const buffer = new Float32Array(
              memory.buffer,
              ptr,
            );

            let idx = 0;
            while (buffer[idx] === 1.0) {
              rects.push({
                x: buffer[idx + 1] as number,
                y: buffer[idx + 2] as number,
                width: buffer[idx + 3] as number,
                height: buffer[idx + 4] as number,
              });
              idx += 5;
            }

            // Buffer is reply-arena owned: valid until the next wasm call,
            // never freed by the client.
            return rects;
          }),
        ),
      ),
      catchError("Node_getClientRects"),
    ),
    Node_getBoundingClientRect: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            // ClientRect is 4 f32 values in a scratch buffer
            // Must copy immediately as buffer will be reused
            const array = new Float32Array(
              memory.buffer,
              ptr,
              4,
            );
            return {
              x: array[0] as number,
              y: array[1] as number,
              width: array[2] as number,
              height: array[3] as number,
            };
          }),
        ),
      ),
      catchError("Node_getBoundingClientRect"),
    ),
    Tree_computeStyles: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_computeStyles"),
    ),
    Tree_buildLayoutTree: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_buildLayoutTree"),
    ),
    Tree_computeLayout: pipe(
      function_(),
      args(
        tuple([number(), zigString, zigString]),
      ),
      returns(void_()),
      catchError("Tree_computeLayout"),
    ),
    Tree_paintSimple: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_paintSimple"),
    ),
    Tree_paintApp: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_paintApp"),
    ),
    Tree_consumeEvents: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          optional(boolean(), false),
        ]),
      ),
      returns(number()),
      catchError("Tree_consumeEvents"),
    ),
    Tree_caretPositionFromPoint: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(boundaryPointSchema),
      catchError("Tree_caretPositionFromPoint"),
    ),
    Tree_enableInputManager: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_enableInputManager"),
    ),
    Tree_disableInputManager: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_disableInputManager"),
    ),
    Tree_getElementById: pipe(
      function_(),
      args(tuple([number(), zigString])),
      returns(number()),
      catchError("Tree_getElementById"),
    ),
    Node_getAttribute: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(
        pipe(
          // Optional returns 0 for null or the pointer value
          union([literal(0), number()]),
          transform((ptr): string | null => {
            // Check for null (optional returned 0)
            if (ptr === 0) {
              return null;
            }

            // Read null-terminated string from memory
            const memoryArray = new Uint8Array(
              memory.buffer,
            );
            let end = ptr;
            while (memoryArray[end] !== 0) {
              end++;
            }

            // Decode the string
            const decoder = new TextDecoder();
            return decoder.decode(
              memoryArray.slice(ptr, end),
            );
          }),
        ),
      ),
      catchError("Node_getAttribute"),
    ),
    Node_setAttribute: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          zigString,
          zigString,
        ]),
      ),
      returns(void_()),
      catchError("Node_setAttribute"),
    ),
    Node_hasAttribute: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(booleanish),
      catchError("Node_hasAttribute"),
    ),
    Node_removeAttribute: pipe(
      function_(),
      args(
        tuple([number(), number(), zigString]),
      ),
      returns(void_()),
      catchError("Node_removeAttribute"),
    ),
    Node_getScrollTop: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollTop"),
    ),
    Node_getScrollLeft: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollLeft"),
    ),
    Node_setScrollTop: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(void_()),
      catchError("Node_setScrollTop"),
    ),
    Node_setScrollLeft: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(void_()),
      catchError("Node_setScrollLeft"),
    ),
    Node_getScrollHeight: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollHeight"),
    ),
    Node_getScrollWidth: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollWidth"),
    ),
    Node_getClientHeight: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getClientHeight"),
    ),
    Node_getClientWidth: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getClientWidth"),
    ),
    Node_getScrollTopMax: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollTopMax"),
    ),
    Node_getScrollLeftMax: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("Node_getScrollLeftMax"),
    ),
    Node_canScroll: pipe(
      function_(),
      args(tuple([number(), number(), number(), number()])),
      returns(booleanish),
      catchError("Node_canScroll"),
    ),
    Tree_hitTest: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            const array = new Uint32Array(
              memory.buffer,
              ptr,
              2,
            );
            if (array[0] === 0) return null;
            return {
              id: array[0] as number,
              type: array[1] as number,
            };
          }),
        ),
      ),
      catchError("Tree_hitTest"),
    ),
    Tree_hitTestList: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            const array = new Uint32Array(
              memory.buffer,
              ptr,
            );
            const results: {
              id: number;
              type: number;
            }[] = [];
            let i = 0;
            while (array[i] !== 0) {
              if (i > 1024) {
                break;
              }
              results.push({
                id: array[i] as number,
                type: array[i + 1] as number,
              });
              i += 2;
            }
            // setTimeout(() => {
            //   module.Tree_deinitHitTestList(ptr);
            // }, 0);
            // module.Tree_deinitHitTestList(ptr);
            return results;
          }),
        ),
      ),
      catchError("Tree_hitTestList"),
    ),
    Tree_deinitHitTestList: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Tree_deinitHitTestList"),
    ),
    Tree_getNodeInvalidationStatus: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError(
        "Tree_getNodeInvalidationStatus",
      ),
    ),
    Tree_createSelection: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(number()),
      catchError("Tree_createSelection"),
    ),
    Tree_removeSelection: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Tree_removeSelection"),
    ),
    Selection_getFocusPosition: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            if (ptr === 0) {
              return null;
            }
            const array = new Float32Array(
              memory.buffer,
              ptr,
              2,
            );
            return {
              x: array[0] as number,
              y: array[1] as number,
            };
          }),
        ),
      ),
      catchError("Selection_getFocusPosition"),
    ),
    Selection_getAnchor: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(boundaryPointSchema),
      catchError("Selection_getAnchor"),
    ),
    Selection_getFocus: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(boundaryPointSchema),
      catchError("Selection_getFocus"),
    ),
    Selection_setAnchor: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(void_()),
      catchError("Selection_setAnchor"),
    ),
    Selection_setFocus: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(void_()),
      catchError("Selection_setFocus"),
    ),
    Selection_getDirection: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(
        union([
          literal(1),
          literal(-1),
          literal(0),
        ]),
      ),
      catchError("Selection_getDirection"),
    ),
    Selection_modify: pipe(
      function_(),
      args(
        tuple([
          number(), // tree
          number(), // selection_id
          number(), // alter
          number(), // direction
          number(), // granularity
          number(), // ghost_position
        ]),
      ),
      returns(void_()),
      catchError("Selection_modify"),
    ),
    Selection_deleteFromDocument: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Selection_deleteFromDocument"),
    ),
    Selection_collapseToStart: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Selection_collapseToStart"),
    ),
    Selection_collapseToEnd: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Selection_collapseToEnd"),
    ),
    Selection_isCollapsed: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(booleanish),
      catchError("Selection_isCollapsed"),
    ),
    Range_deleteContents: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("Range_deleteContents"),
    ),
    Range_setStart: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(void_()),
      catchError("Range_setStart"),
    ),
    Range_setEnd: pipe(
      function_(),
      args(
        tuple([
          number(),
          number(),
          number(),
          number(),
        ]),
      ),
      returns(void_()),
      catchError("Range_setEnd"),
    ),
    Range_collapse: pipe(
      function_(),
      args(
        tuple([number(), number(), boolean()]),
      ),
      returns(void_()),
      catchError("Range_collapse"),
    ),
    Range_insertNode: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(void_()),
      catchError("Range_insertNode"),
    ),

    Tree_getBoundaryPointPosition: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(
        pipe(
          number(),
          transform((ptr) => {
            const array = new Float32Array(
              memory.buffer,
              ptr,
              2,
            );
            return {
              x: array[0] as number,
              y: array[1] as number,
            };
          }),
        ),
      ),
      catchError("Tree_getBoundaryPointPosition"),
    ),

    Renderer_init: pipe(
      function_(),
      args(tuple([])),
      returns(number()),
      catchError("Renderer_init"),
    ),
    Renderer_deinit: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("Renderer_deinit"),
    ),

    TermInfo_initFromMemory: pipe(
      function_(),
      args(tuple([zigBuffer])),
      returns(number()),
      catchError("TermInfo_initFromMemory"),
    ),
    TermInfo_deinit: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("TermInfo_deinit"),
    ),

    // InputManager_init: pipe(
    //   function_(),
    //   args(tuple([])),
    //   returns(number()),
    // ),
    // InputManager_deinit: pipe(
    //   function_(),
    //   args(tuple([number()])),
    //   returns(void_()),
    // ),

    ArrayList_init: pipe(
      function_(),
      args(tuple([])),
      returns(number()),
      catchError("ArrayList_init"),
    ),
    ArrayList_deinit: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("ArrayList_deinit"),
    ),
    ArrayList_appendUnusedSlice: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(number()),
      catchError("ArrayList_appendUnusedSlice"),
    ),
    ArrayList_clearRetainingCapacity: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError(
        "ArrayList_clearRetainingCapacity",
      ),
    ),
    ArrayList_getLength: pipe(
      function_(),
      args(tuple([number()])),
      returns(number()),
      catchError("ArrayList_getLength"),
    ),
    ArrayList_setLength: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("ArrayList_setLength"),
    ),
    ArrayList_getPointer: pipe(
      function_(),
      args(tuple([number()])),
      returns(number()),
      catchError("ArrayList_getPointer"),
    ),

    ArrayList_dump: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("ArrayList_dump"),
    ),

    allocBuffer: pipe(
      function_(),
      args(tuple([number()])),
      returns(number()),
      catchError("allocBuffer"),
    ),
    freeBuffer: pipe(
      function_(),
      args(tuple([number(), number()])),
      returns(void_()),
      catchError("freeBuffer"),
    ),
    allocNullTerminatedBuffer: pipe(
      function_(),
      args(tuple([number()])),
      returns(number()),
      catchError("allocNullTerminatedBuffer"),
    ),
    freeNullTerminatedBuffer: pipe(
      function_(),
      args(tuple([number()])),
      returns(void_()),
      catchError("freeNullTerminatedBuffer"),
    ),
    memcopy: pipe(
      function_(),
      args(tuple([number(), number(), number()])),
      returns(void_()),
      catchError("memcopy"),
    ),
    detectLeaks: pipe(
      function_(),
      args(tuple([])),
      returns(booleanish),
      catchError("detectLeaks"),
    ),

    EventBuffer: instance(WebAssembly.Global),
  });
};
