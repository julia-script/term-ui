

import React, { useState } from "react"
import { useQuery, useSuspenseQuery } from "@tanstack/react-query"
import { useDevTools } from "./DevToolsContext"

export const DomTree = () => {
  const { trpcClient } = useDevTools()

  const { data, isLoading, error } = useQuery({
    queryKey: ["dom-tree"],
    // networkMode: "always",
    queryFn: () => {
      // console.log("queryFn")
      return trpcClient.status.query()
    },
  

  })

  // console.log("data", data)

  // if (isLoading) return <text>Loading...</text>
  // if (error) return <text>Error: {error.message}</text>
  if (data) {
    return <DomTreeItem nodeId={data.root} />
  }
  return <text>No data</text>;
};

const DomTreeItem = ({ nodeId }: { nodeId: number }) => {
  const { trpcClient } = useDevTools()
  const [isCollapsed, setIsCollapsed] = useState(false)

  const { data, isLoading, error } = useQuery({
    queryKey: ["dom-tree-item", nodeId],
    queryFn: () => {
      return trpcClient.getNodeInfo.query(nodeId)
    },
  })

  if (isLoading) return <text>Loading...</text>
  if (error) return <text>Error: {error.message}</text>

  return <view>
    <text>{data?.type}</text>
    <view>
      {/* {data?.children.map((child) => (
        <DomTreeItem nodeId={child.id} />
      ))} */}
    </view>
  </view> 
}