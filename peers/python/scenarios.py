from __future__ import annotations

from typing import Any

from ag_ui.core import (
    EventType,
    ReasoningEndEvent,
    ReasoningMessageContentEvent,
    ReasoningMessageEndEvent,
    ReasoningMessageStartEvent,
    ReasoningStartEvent,
    RunErrorEvent,
    RunFinishedEvent,
    RunStartedEvent,
    StateDeltaEvent,
    StateSnapshotEvent,
    TextMessageContentEvent,
    TextMessageEndEvent,
    TextMessageStartEvent,
    ToolCallArgsEvent,
    ToolCallEndEvent,
    ToolCallResultEvent,
    ToolCallStartEvent,
)
from ag_ui.core.events import RunFinishedInterruptOutcome

SCENARIOS = ("echo", "tools", "state", "reasoning", "interrupt", "resume")

CAPABILITIES = {
    "identity": {"name": "parity"},
    "transport": {"streaming": True},
}


def last_user_text(payload: dict[str, Any]) -> str:
    text = ""
    for message in payload.get("messages") or []:
        if message.get("role") == "user" and isinstance(message.get("content"), str):
            text = message["content"]
    return text


def _thread(payload: dict[str, Any]) -> str:
    return payload.get("threadId") or payload.get("thread_id") or "thread"


def _run(payload: dict[str, Any]) -> str:
    return payload.get("runId") or payload.get("run_id") or "run"


def events_for(payload: dict[str, Any]) -> list[Any]:
    thread_id = _thread(payload)
    run_id = _run(payload)
    started = RunStartedEvent(type=EventType.RUN_STARTED, thread_id=thread_id, run_id=run_id)
    finished = RunFinishedEvent(type=EventType.RUN_FINISHED, thread_id=thread_id, run_id=run_id)
    scenario = last_user_text(payload)
    if scenario == "tools":
        return [
            started,
            ToolCallStartEvent(
                type=EventType.TOOL_CALL_START, tool_call_id="tc-1", tool_call_name="echo"
            ),
            ToolCallArgsEvent(type=EventType.TOOL_CALL_ARGS, tool_call_id="tc-1", delta='{"x":1}'),
            ToolCallEndEvent(type=EventType.TOOL_CALL_END, tool_call_id="tc-1"),
            ToolCallResultEvent(
                type=EventType.TOOL_CALL_RESULT,
                message_id="msg-tool",
                tool_call_id="tc-1",
                content="ok",
                role="tool",
            ),
            finished,
        ]
    if scenario == "state":
        return [
            started,
            StateSnapshotEvent(type=EventType.STATE_SNAPSHOT, snapshot={"count": 0}),
            StateDeltaEvent(
                type=EventType.STATE_DELTA, delta=[{"op": "replace", "path": "/count", "value": 1}]
            ),
            finished,
        ]
    if scenario == "reasoning":
        mid = "msg-reason"
        return [
            started,
            ReasoningStartEvent(type=EventType.REASONING_START, message_id=mid),
            ReasoningMessageStartEvent(
                type=EventType.REASONING_MESSAGE_START, message_id=mid, role="reasoning"
            ),
            ReasoningMessageContentEvent(
                type=EventType.REASONING_MESSAGE_CONTENT, message_id=mid, delta="think"
            ),
            ReasoningMessageEndEvent(type=EventType.REASONING_MESSAGE_END, message_id=mid),
            ReasoningEndEvent(type=EventType.REASONING_END, message_id=mid),
            finished,
        ]
    if scenario == "interrupt":
        return [
            started,
            RunFinishedEvent(
                type=EventType.RUN_FINISHED,
                thread_id=thread_id,
                run_id=run_id,
                outcome=RunFinishedInterruptOutcome(
                    type="interrupt",
                    interrupts=[{"id": "int-1", "reason": "tool_call", "message": "approve?"}],
                ),
            ),
        ]
    if scenario == "resume":
        resume = payload.get("resume") or []
        first = resume[0] if resume else {}
        interrupt_id = first.get("interruptId") or first.get("interrupt_id")
        if interrupt_id != "int-1" or first.get("status") != "resolved":
            return [
                started,
                RunErrorEvent(
                    type=EventType.RUN_ERROR, message="resume missing int-1", code="resume"
                ),
            ]
        return [
            started,
            TextMessageStartEvent(
                type=EventType.TEXT_MESSAGE_START, message_id="msg-resume", role="assistant"
            ),
            TextMessageContentEvent(
                type=EventType.TEXT_MESSAGE_CONTENT, message_id="msg-resume", delta="approved"
            ),
            TextMessageEndEvent(type=EventType.TEXT_MESSAGE_END, message_id="msg-resume"),
            finished,
        ]
    return [
        started,
        TextMessageStartEvent(
            type=EventType.TEXT_MESSAGE_START, message_id="msg-echo", role="assistant"
        ),
        TextMessageContentEvent(
            type=EventType.TEXT_MESSAGE_CONTENT, message_id="msg-echo", delta="pong"
        ),
        TextMessageEndEvent(type=EventType.TEXT_MESSAGE_END, message_id="msg-echo"),
        finished,
    ]


def summarize(events: list[Any]) -> dict[str, Any]:
    types: list[str] = []
    text = ""
    reasoning = ""
    tool = None
    snapshot_count = None
    delta_value = None
    outcome = ""
    interrupt_id = ""
    for event in events:
        kind = event.type.value if hasattr(event.type, "value") else str(event.type)
        types.append(kind)
        if kind == "TEXT_MESSAGE_CONTENT":
            text += getattr(event, "delta", "") or ""
        elif kind == "REASONING_MESSAGE_CONTENT":
            reasoning += getattr(event, "delta", "") or ""
        elif kind == "TOOL_CALL_START" and tool is None:
            tool = getattr(event, "tool_call_name", None)
        elif kind == "STATE_SNAPSHOT":
            snapshot = getattr(event, "snapshot", None)
            if isinstance(snapshot, dict):
                snapshot_count = snapshot.get("count")
        elif kind == "STATE_DELTA":
            delta = getattr(event, "delta", None) or []
            if delta:
                first = delta[0]
                delta_value = first.get("value") if isinstance(first, dict) else None
        elif kind == "RUN_FINISHED":
            raw = getattr(event, "outcome", None)
            if raw is not None:
                outcome = getattr(raw, "type", "") or ""
                interrupts = getattr(raw, "interrupts", None) or []
                if interrupts:
                    interrupt_id = getattr(interrupts[0], "id", "") or ""
    return {
        "types": types,
        "text": text,
        "reasoning": reasoning,
        "tool": tool,
        "snapshotCount": snapshot_count,
        "deltaValue": delta_value,
        "outcome": outcome,
        "interruptId": interrupt_id,
    }


def run_input(scenario: str) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "threadId": f"t-{scenario}",
        "runId": f"r-{scenario}",
        "messages": [{"id": f"u-{scenario}", "role": "user", "content": scenario}],
        "tools": [],
        "context": [],
        "state": {},
        "forwardedProps": {},
    }
    if scenario == "resume":
        payload["resume"] = [
            {"interruptId": "int-1", "status": "resolved", "payload": {"approved": True}}
        ]
    return payload
