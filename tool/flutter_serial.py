#!/usr/bin/env python3
"""Run Flutter under a repository lock shared by linked worktrees."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


@contextmanager
def repository_lock(path: Path):
    # Do not unlink the file: waiters must continue locking the same inode.
    with path.open("a+b") as lock:
        if os.name == "nt":
            import msvcrt

            if lock.seek(0, os.SEEK_END) == 0:
                lock.write(b"\0")
                lock.flush()
            while True:
                try:
                    lock.seek(0)
                    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError as error:
                    if error.errno not in (13, 36):
                        raise
                    time.sleep(0.1)
            try:
                yield
            finally:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)


def run_process(command: list[str], cwd: Path, *, capture: bool = False):
    """Forward cancellation, wait for the child, and preserve its exit status."""
    child = None
    pending_signal = None

    def forward(signum, _frame):
        nonlocal pending_signal
        pending_signal = signum
        if child is None or child.poll() is not None:
            return
        try:
            if os.name == "nt":
                if signum == signal.SIGINT:
                    child.send_signal(signal.CTRL_BREAK_EVENT)
                else:
                    child.terminate()
            else:
                os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass

    previous = {
        sig: signal.signal(sig, forward)
        for sig in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        if pending_signal is not None:
            return 128 + pending_signal, "" if capture else None
        options = (
            {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
            if os.name == "nt" else {"start_new_session": True}
        )
        child = subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE if capture else None,
            text=True,
            **options,
        )
        if pending_signal is not None:
            forward(pending_signal, None)
        output, _ = child.communicate()
        code = child.returncode
        return (128 - code if code < 0 else code), output
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def flutter_command(root: Path) -> list[str]:
    if shutil.which("fvm"):
        return ["fvm", "flutter"]
    executable = "flutter.bat" if os.name == "nt" else "flutter"
    sdk = root / ".fvm/flutter_sdk/bin" / executable
    if sdk.is_file():
        return [str(sdk)]
    if shutil.which("flutter"):
        return ["flutter"]
    raise RuntimeError("未找到 Flutter；请按 DEVELOPMENT.md 配置固定 SDK。")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "flutter_args", nargs=argparse.REMAINDER,
        help="Flutter 子命令及原样传递的参数",
    )
    args = parser.parse_args(argv).flutter_args
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        parser.error("需要 Flutter 子命令，例如 test 或 run")
    try:
        root = Path(subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True,
        ).strip())
        common = Path(subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], cwd=root, text=True,
        ).strip())
        if not common.is_absolute():
            common = root / common
        pinned = json.loads((root / ".fvmrc").read_text())["flutter"]
        command = flutter_command(root)
        with repository_lock(common.resolve() / "bnbu-flutter-serial.lock"):
            code, version = run_process(
                command + ["--version", "--machine"], root, capture=True,
            )
            if code:
                return code
            if json.loads(version).get("frameworkVersion") != pinned:
                raise RuntimeError(f"当前 SDK 与 .fvmrc 不一致，需要 Flutter {pinned}。")
            code, _ = run_process(command + args, root)
            return code
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Flutter 串行入口失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
