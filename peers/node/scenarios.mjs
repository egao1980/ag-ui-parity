import { EventType } from "@ag-ui/core";

export const SCENARIOS = ["echo", "tools", "state", "reasoning", "interrupt", "resume"];

export const CAPABILITIES = {
  identity: { name: "parity" },
  transport: { streaming: true },
};

function lastUserText(input) {
  const messages = input?.messages ?? [];
  let text = "";
  for (const m of messages) {
    if (m?.role === "user" && typeof m.content === "string") text = m.content;
  }
  return text;
}

function started(input) {
  return {
    type: EventType.RUN_STARTED,
    threadId: input.threadId ?? "thread",
    runId: input.runId ?? "run",
  };
}

function finished(input, extra = {}) {
  return {
    type: EventType.RUN_FINISHED,
    threadId: input.threadId ?? "thread",
    runId: input.runId ?? "run",
    ...extra,
  };
}

export function eventsFor(input) {
  const scenario = lastUserText(input);
  switch (scenario) {
    case "tools":
      return [
        started(input),
        { type: EventType.TOOL_CALL_START, toolCallId: "tc-1", toolCallName: "echo" },
        { type: EventType.TOOL_CALL_ARGS, toolCallId: "tc-1", delta: "{\"x\":1}" },
        { type: EventType.TOOL_CALL_END, toolCallId: "tc-1" },
        {
          type: EventType.TOOL_CALL_RESULT,
          messageId: "msg-tool",
          toolCallId: "tc-1",
          content: "ok",
          role: "tool",
        },
        finished(input),
      ];
    case "state":
      return [
        started(input),
        { type: EventType.STATE_SNAPSHOT, snapshot: { count: 0 } },
        {
          type: EventType.STATE_DELTA,
          delta: [{ op: "replace", path: "/count", value: 1 }],
        },
        finished(input),
      ];
    case "reasoning":
      return [
        started(input),
        { type: EventType.REASONING_START, messageId: "msg-reason" },
        {
          type: EventType.REASONING_MESSAGE_START,
          messageId: "msg-reason",
          role: "reasoning",
        },
        {
          type: EventType.REASONING_MESSAGE_CONTENT,
          messageId: "msg-reason",
          delta: "think",
        },
        { type: EventType.REASONING_MESSAGE_END, messageId: "msg-reason" },
        { type: EventType.REASONING_END, messageId: "msg-reason" },
        finished(input),
      ];
    case "interrupt":
      return [
        started(input),
        finished(input, {
          outcome: {
            type: "interrupt",
            interrupts: [{ id: "int-1", reason: "tool_call", message: "approve?" }],
          },
        }),
      ];
    case "resume": {
      const resume = input?.resume ?? [];
      const first = resume[0];
      if (first?.interruptId !== "int-1" || first?.status !== "resolved") {
        return [
          started(input),
          { type: EventType.RUN_ERROR, message: "resume missing int-1", code: "resume" },
        ];
      }
      return [
        started(input),
        { type: EventType.TEXT_MESSAGE_START, messageId: "msg-resume", role: "assistant" },
        { type: EventType.TEXT_MESSAGE_CONTENT, messageId: "msg-resume", delta: "approved" },
        { type: EventType.TEXT_MESSAGE_END, messageId: "msg-resume" },
        finished(input),
      ];
    }
    case "echo":
    default:
      return [
        started(input),
        { type: EventType.TEXT_MESSAGE_START, messageId: "msg-echo", role: "assistant" },
        { type: EventType.TEXT_MESSAGE_CONTENT, messageId: "msg-echo", delta: "pong" },
        { type: EventType.TEXT_MESSAGE_END, messageId: "msg-echo" },
        finished(input),
      ];
  }
}

export function summarize(events) {
  const types = events.map((e) => e.type);
  let text = "";
  let reasoning = "";
  let tool = null;
  let snapshotCount = null;
  let deltaValue = null;
  let outcome = "";
  let interruptId = "";
  for (const e of events) {
    if (e.type === EventType.TEXT_MESSAGE_CONTENT) text += e.delta ?? "";
    if (e.type === EventType.REASONING_MESSAGE_CONTENT) reasoning += e.delta ?? "";
    if (e.type === EventType.TOOL_CALL_START && !tool) tool = e.toolCallName ?? null;
    if (e.type === EventType.STATE_SNAPSHOT) snapshotCount = e.snapshot?.count ?? null;
    if (e.type === EventType.STATE_DELTA) deltaValue = e.delta?.[0]?.value ?? null;
    if (e.type === EventType.RUN_FINISHED) {
      outcome = e.outcome?.type ?? "";
      interruptId = e.outcome?.interrupts?.[0]?.id ?? "";
    }
  }
  return { types, text, reasoning, tool, snapshotCount, deltaValue, outcome, interruptId };
}

export function runInput(scenario) {
  const input = {
    threadId: `t-${scenario}`,
    runId: `r-${scenario}`,
    messages: [{ id: `u-${scenario}`, role: "user", content: scenario }],
    tools: [],
    context: [],
    state: {},
    forwardedProps: {},
  };
  if (scenario === "resume") {
    input.resume = [{ interruptId: "int-1", status: "resolved", payload: { approved: true } }];
  }
  return input;
}
