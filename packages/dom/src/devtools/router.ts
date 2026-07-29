import { publicProcedure, router } from "./trpc";
import type { Document } from "../Document.js";
import { z } from "zod/v4";
import { TextElement } from "../TextElement";
import EventEmitter, { on } from "node:events";
import { tracked } from "@trpc/server";

export const createRouter = (
  document: Document,
) => {
  const ee = new EventEmitter<{
    render: [boolean];
  }>();
  return {
    router: router({
      status: publicProcedure.query(async () => {
        return {
          tree: document.tree.ptr,
          root: document.root.id,
          status: "ok",
        };
      }),
      getNodeInfo: publicProcedure
        .input(z.number())
        .query(async ({ input }) => {
          const node =
            document.getOrAddElement(input);
          if (node instanceof TextElement) {
            return {
              id: node.id,
              type: "TEXT_NODE" as const,
              text: node.getText(),
            };
          }

          return {
            id: node.id,
            type: "ELEMENT_NODE" as const,
            children: node
              .getChildren()
              .map((child) => ({
                id: child.id,
                type: child.getKindName(),
              })),
          };
        }),
      getDump: publicProcedure.query(async () => {
        return {
          data: document.tree.dump(),
        };
      }),
      onRender: publicProcedure.subscription(
        async function* (opts) {
          ee.emit("render", true)
          for await (const [value] of on(ee, "render", {
            signal: opts.signal,

          })) {
            yield true;
          }
        },
      ),
    }),
    ee,
  };
};

export type AppRouter = ReturnType<
  typeof createRouter
>["router"];
