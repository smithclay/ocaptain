"""Shared utilities for VM providers."""

from __future__ import annotations

import logging
import subprocess  # nosec: B404
import sys
import time
from collections.abc import Callable
from io import BytesIO
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from ..provider import VM


class HasStdout(Protocol):
    """Protocol for objects with a stdout attribute."""

    stdout: str


class ConnectionLike(Protocol):
    """Protocol for connection objects with run() and put() methods."""

    def run(self, cmd: str, *, hide: bool = False, warn: bool = False) -> HasStdout:
        """Run a command."""
        ...

    def put(self, local: BytesIO, remote: str) -> None:
        """Upload a file."""
        ...


def run_cli_command(
    cmd: list[str], *, check: bool = True, description: str = "command"
) -> subprocess.CompletedProcess[str]:
    """Run a CLI command with standard error handling.

    Args:
        cmd: Command and arguments to run
        check: If True, raise on non-zero exit
        description: Description for error messages

    Returns:
        CompletedProcess with stdout/stderr
    """
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)  # nosec: B603
    if result.returncode != 0 and check:
        print(f"{description} failed: {' '.join(cmd)}", file=sys.stderr)
        print(f"stderr: {result.stderr}", file=sys.stderr)
        print(f"stdout: {result.stdout}", file=sys.stderr)
        result.check_returncode()
    return result


def setup_ssh_keys(connection: ConnectionLike, private_key: str, public_key: str) -> None:
    """Set up SSH keys on a VM via a connection.

    Creates .ssh directory, writes private key, and appends public key to authorized_keys.

    Args:
        connection: Connection object with run() and put() methods
        private_key: Private key content
        public_key: Public key content
    """
    # Get home directory
    result = connection.run("echo $HOME", hide=True)
    home = result.stdout.strip()
    ssh_dir = f"{home}/.ssh"

    # Ensure .ssh directory exists with correct permissions
    connection.run(f"mkdir -p {ssh_dir} && chmod 700 {ssh_dir}")

    # Write private key
    connection.put(BytesIO(private_key.encode()), f"{ssh_dir}/id_ed25519")
    connection.run(f"chmod 600 {ssh_dir}/id_ed25519")

    # Append public key to authorized_keys
    connection.put(BytesIO(public_key.encode()), f"{ssh_dir}/ocaptain_key.pub")
    connection.run(f"cat {ssh_dir}/ocaptain_key.pub >> {ssh_dir}/authorized_keys")
    connection.run(f"chmod 600 {ssh_dir}/authorized_keys")


def install_claude_code(connection: ConnectionLike) -> None:
    """Install or update Claude Code on a VM.

    Args:
        connection: Connection object with run() method
    """
    connection.run("curl -fsSL https://claude.ai/install.sh | bash", hide=True)


def poll_until_ready(
    check_fn: Callable[[], bool],
    *,
    timeout: int = 300,
    interval: int = 5,
    vm: VM | None = None,
    logger: logging.Logger | None = None,
) -> bool:
    """Poll until a check function returns True.

    Args:
        check_fn: Function that returns True when ready, raises on failure
        timeout: Maximum time to wait in seconds
        interval: Time between retries in seconds
        vm: Optional VM for logging
        logger: Optional logger for debug messages

    Returns:
        True if ready, False if timeout
    """
    start = time.time()

    while time.time() - start < timeout:
        try:
            if check_fn():
                return True
        except KeyboardInterrupt:
            raise
        except Exception as e:
            if logger and vm:
                logger.debug("Check failed for %s: %s", vm.name, e)
        time.sleep(interval)

    return False
