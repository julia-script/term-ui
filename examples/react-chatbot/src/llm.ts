// Streaming chat-completion client. Picks a backend from the environment:
// OPENROUTER_API_KEY > OPENAI_API_KEY > a keyless demo bot, so the example
// always runs. Both real backends speak the OpenAI chat-completions SSE
// protocol, so one parser covers them.

export type ChatMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

type Backend = {
  label: string;
  stream: (
    messages: ChatMessage[],
    signal: AbortSignal,
  ) => AsyncGenerator<string>;
};

const SYSTEM_PROMPT =
  "You are a concise assistant living inside a terminal UI demo. " +
  "Answer briefly in plain text: no markdown, no code fences unless asked for code.";

async function* streamOpenAiCompatible(
  url: string,
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  signal: AbortSignal,
): AsyncGenerator<string> {
  const response = await fetch(url, {
    method: "POST",
    signal,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      stream: true,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        ...messages,
      ],
    }),
  });
  if (!response.ok || !response.body) {
    const detail = await response
      .text()
      .catch(() => "");
    throw new Error(
      `${response.status} ${response.statusText}${detail ? `: ${detail.slice(0, 200)}` : ""}`,
    );
  }
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk as Uint8Array, {
      stream: true,
    });
    // SSE: events separated by newlines; each data line is a JSON delta
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) continue;
      const payload = trimmed.slice(5).trim();
      if (payload === "[DONE]") return;
      try {
        const token: unknown =
          JSON.parse(payload).choices?.[0]?.delta
            ?.content;
        if (typeof token === "string" && token) {
          yield token;
        }
      } catch {
        // OpenRouter interleaves ": OPENROUTER PROCESSING" comments and
        // occasional non-JSON keep-alives; skip them
      }
    }
  }
}

const DEMO_LINES = [
  "I'm the demo bot - no API key was found, so I can only echo. ",
  "Set OPENROUTER_API_KEY or OPENAI_API_KEY to talk to a real model. ",
  "You said: ",
];

async function* streamDemo(
  messages: ChatMessage[],
  signal: AbortSignal,
): AsyncGenerator<string> {
  const last =
    messages[messages.length - 1]?.content ?? "";
  const full =
    DEMO_LINES.join("") + `"${last}"`;
  for (const word of full.split(/(?<= )/)) {
    if (signal.aborted) return;
    yield word;
    await new Promise((r) => setTimeout(r, 40));
  }
}

export const pickBackend = (): Backend => {
  const openRouterKey =
    process.env.OPENROUTER_API_KEY;
  if (openRouterKey) {
    const model =
      process.env.OPENROUTER_MODEL ??
      "openai/gpt-4o-mini";
    return {
      label: `openrouter · ${model}`,
      stream: (messages, signal) =>
        streamOpenAiCompatible(
          "https://openrouter.ai/api/v1/chat/completions",
          openRouterKey,
          model,
          messages,
          signal,
        ),
    };
  }
  const openAiKey = process.env.OPENAI_API_KEY;
  if (openAiKey) {
    const model =
      process.env.OPENAI_MODEL ?? "gpt-4o-mini";
    return {
      label: `openai · ${model}`,
      stream: (messages, signal) =>
        streamOpenAiCompatible(
          "https://api.openai.com/v1/chat/completions",
          openAiKey,
          model,
          messages,
          signal,
        ),
    };
  }
  return {
    label: "demo bot (no api key)",
    stream: streamDemo,
  };
};
