#!/usr/bin/env python3
from __future__ import annotations

import sys

import uvicorn
from ag_ui.encoder import EventEncoder
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

from scenarios import CAPABILITIES, events_for


async def handle(request: Request):
    if request.method == "GET":
        return JSONResponse(CAPABILITIES)
    payload = await request.json()
    encoder = EventEncoder()

    async def stream():
        for event in events_for(payload):
            yield encoder.encode(event)

    return StreamingResponse(stream(), media_type="text/event-stream")


def main() -> None:
    port = int(sys.argv[1] if len(sys.argv) > 1 else 0)
    if port <= 0:
        print("usage: http_server.py <port>", file=sys.stderr)
        raise SystemExit(2)
    app = Starlette(routes=[Route("/", handle, methods=["GET", "POST"])])
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    main()
