import { HttpAgent } from "@ag-ui/client";
import { CAPABILITIES, SCENARIOS, runInput, summarize } from "./scenarios.mjs";

const url = process.argv[2];
if (!url) {
  console.error("usage: http-client.mjs <url>");
  process.exit(2);
}

async function fetchCapabilities() {
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`GET capabilities HTTP ${res.status}`);
  return res.json();
}

async function runScenario(scenario) {
  const input = runInput(scenario);
  const events = [];
  const agent = new HttpAgent({
    url,
    threadId: input.threadId,
    initialMessages: input.messages,
    initialState: input.state,
  });
  await agent.runAgent(
    {
      runId: input.runId,
      tools: input.tools,
      context: input.context,
      forwardedProps: input.forwardedProps,
      resume: input.resume,
    },
    {
      onEvent: ({ event }) => {
        if (event) events.push(event);
      },
    },
  );
  return summarize(events);
}

const caps = await fetchCapabilities();
const scenarios = {};
for (const name of SCENARIOS) {
  scenarios[name] = await runScenario(name);
}

process.stdout.write(
  `${JSON.stringify({
    name: caps?.identity?.name ?? CAPABILITIES.identity.name,
    streaming: Boolean(caps?.transport?.streaming),
    scenarios,
  })}\n`,
);
process.exit(0);
