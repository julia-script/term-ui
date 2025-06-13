import * as v from "valibot";
import {
  defineProcedure,
  defineRouter,
} from "../rpc";

export const clientRouter = defineRouter({
  ping: defineProcedure(
    v.literal("ping"),
    ({ input }) => {
      return "pong";
    },
  ),
});

export type ClientRouter = typeof clientRouter;
