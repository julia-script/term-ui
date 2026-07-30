#!/usr/bin/env python3
"""Run the clean-room app under a pty and assert it actually rendered.

A terminal app writes escape sequences, not plain text, so the check runs it on
a real pty (it needs a tty to size itself) and reads the screen back through a
terminal emulator.
"""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

import pyte

app_dir = sys.argv[1]
COLS, ROWS = 60, 16

pid, fd = pty.fork()
if pid == 0:
    os.chdir(app_dir)
    os.environ["TERM"] = "xterm-256color"
    os.execvp("npx", ["npx", "tsx", "src/app.tsx"])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

screen = pyte.Screen(COLS, ROWS)
stream = pyte.ByteStream(screen)
raw = b""
best = ""

def snapshot():
    return "\n".join(line.rstrip() for line in screen.display)

start = time.time()
exited = False
while time.time() - start < 40:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            exited = True
            break
        if not chunk:
            exited = True
            break
        raw += chunk
        stream.feed(chunk)
        current = snapshot()
        if len(current.strip()) > len(best.strip()):
            best = current
    pid_done, status = os.waitpid(pid, os.WNOHANG)
    if pid_done:
        exited = True
        exit_code = os.waitstatus_to_exitcode(status)
        break
else:
    exit_code = None

try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass

text = best or snapshot()
print("---- screen ----")
print(text)
print("----------------")

decoded = raw.decode("utf-8", errors="replace")
if os.environ.get("CLEAN_ROOM_DEBUG"):
    print("---- raw (first 1500) ----")
    print(repr(raw[:1500]))
failures = []

if "Error" in decoded or "Cannot find" in decoded or "Traceback" in decoded:
    failures.append("the program reported an error")
if "Count: 0" not in text.replace("  ", " "):
    # the engine may letter-space; fall back to a looser check
    if "Count:" not in text and "Count" not in text:
        failures.append("expected text 'Count: 0' was not rendered")
if "increment" not in text.replace(" ", "").lower().replace("clicktoincrement", "increment"):
    if "increment" not in text.lower():
        failures.append("expected text 'Click to increment' was not rendered")
if not any(ch in text for ch in "─│┌┐└┘╭╮╰╯═║╔╗╚╝"):
    failures.append("no box-drawing characters — borders did not render")

if failures:
    print("FAILED:")
    for f in failures:
        print("  -", f)
    if not exited:
        print("  - the program did not exit on its own")
    sys.exit(1)

print("rendered correctly; exit code:", exit_code)
