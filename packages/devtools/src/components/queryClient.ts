import { QueryClient } from "@tanstack/react-query";
import { onlineManager } from "@tanstack/react-query";

export const queryClient = new QueryClient();
queryClient.getQueryCache().subscribe((event) => {
  // console.log("event", event.type, event.query.state)
});
