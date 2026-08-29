#!/usr/bin/env python3
from __future__ import annotations

import json
import sys

import httpx
from ag_ui.core.events import Event
from pydantic import TypeAdapter

from scenarios import CAPABILITIES, SCENARIOS, run_input, summarize

EVENT_ADAPTER = TypeAdapter(Event)


def parse_sse(body: str) -> list[Event]:
    events: list[Event] = []
    data_lines: list[str] = []
    for line in body.splitlines():
        if line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
        elif line == "" and data_lines:
            raw = "\n".join(data_lines)
            data_lines = []
            if raw:
                events.append(EVENT_ADAPTER.validate_json(raw))
    if data_lines:
        raw = "\n".join(data_lines)
        if raw:
            events.append(EVENT_ADAPTER.validate_json(raw))
    return events


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: http_client.py <url>", file=sys.stderr)
        raise SystemExit(2)
    url = sys.argv[1]
    with httpx.Client(timeout=30.0) as client:
        caps = client.get(url, headers={"Accept": "application/json"}).raise_for_status().json()
        scenarios: dict[str, object] = {}
        for name in SCENARIOS:
            res = client.post(
                url,
                json=run_input(name),
                headers={
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                },
            )
            res.raise_for_status()
            scenarios[name] = summarize(parse_sse(res.text))
    print(
        json.dumps(
            {
                "name": (caps.get("identity") or {}).get("name") or CAPABILITIES["identity"]["name"],
                "streaming": bool((caps.get("transport") or {}).get("streaming")),
                "scenarios": scenarios,
            }
        )
    )


if __name__ == "__main__":
    main()
