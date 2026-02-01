"""BoxLite micro-VM provider for local development.

BoxLite runs hardware-isolated micro-VMs locally with sub-second boot times.
Each VM gets its own Linux kernel for true isolation.

Requirements:
- macOS 12+ or Linux with KVM
- Python 3.10+
- boxlite>=0.3.0 (pip install ocaptain[boxlite])
"""

from __future__ import annotations

import asyncio
import logging
import shlex
import time
from typing import TYPE_CHECKING

from fabric import Connection

from ..config import CONFIG, get_ssh_keypair
from ..provider import VM, Provider, VMStatus, register_provider

logger = logging.getLogger(__name__)

if TYPE_CHECKING:
    import boxlite as boxlite_module


def _get_boxlite() -> boxlite_module:
    """Import boxlite, raising helpful error if not installed."""
    try:
        import boxlite

        return boxlite
    except ImportError as e:
        raise ImportError(
            "boxlite not installed. Install with: pip install ocaptain[boxlite]"
        ) from e


@register_provider("boxlite")
class BoxLiteProvider(Provider):
    """Local micro-VM provider using BoxLite.

    VMs are ephemeral and only exist while the provider instance lives.
    """

    def __init__(self) -> None:
        self._boxes: dict[str, object] = {}  # boxlite.SimpleBox instances
        self._vms: dict[str, VM] = {}
        self._loop = asyncio.new_event_loop()
        self._config = CONFIG.providers.get("boxlite", {})

    def __del__(self) -> None:
        """Cleanup event loop on provider destruction."""
        if hasattr(self, "_loop") and self._loop and not self._loop.is_closed():
            self._loop.close()

    def create(self, name: str, *, wait: bool = True) -> VM:
        """Create a new BoxLite VM."""
        return self._loop.run_until_complete(self._create(name, wait))

    async def _create(self, name: str, wait: bool) -> VM:
        """Async implementation of create."""
        boxlite = _get_boxlite()

        image = self._config.get("image", "ubuntu:22.04")
        disk_size_gb = self._config.get("disk_size_gb", 10)  # 10GB default for packages
        box = boxlite.SimpleBox(image, disk_size_gb=disk_size_gb)
        await box.__aenter__()

        try:
            self._boxes[name] = box

            # Bootstrap: install Tailscale, SSH, get IP
            await self._bootstrap_vm(box, name)

            # Get Tailscale IP with status check
            ts_socket = "/run/tailscale/tailscaled.sock"
            status_result = await box.exec(
                "bash", "-c", f"/usr/bin/tailscale --socket={ts_socket} status 2>&1 || true"
            )
            logger.info("Tailscale status for %s: %s", name, status_result.stdout[:200])

            result = await box.exec(
                "bash", "-c", f"/usr/bin/tailscale --socket={ts_socket} ip -4 2>&1 || true"
            )
            ts_ip = result.stdout.strip()

            if not ts_ip or "error" in ts_ip.lower():
                status_info = status_result.stdout[:500]
                raise RuntimeError(
                    f"Tailscale did not return an IP for {name}. Status: {status_info}"
                )

            vm = VM(
                id=name,
                name=name,
                ssh_dest=f"ubuntu@{ts_ip}",
                status=VMStatus.RUNNING,
            )
            self._vms[name] = vm

            if wait and not self.wait_ready(vm):
                raise TimeoutError(f"VM {name} did not become SSH-accessible")

            return vm
        except Exception:
            # Cleanup on failure
            logger.warning("VM creation failed for %s, cleaning up...", name)
            try:
                await box.__aexit__(None, None, None)
            except Exception as cleanup_error:
                logger.error("Failed to cleanup box %s: %s", name, cleanup_error)
            self._boxes.pop(name, None)
            self._vms.pop(name, None)
            raise

    async def _bootstrap_vm(self, box: object, name: str) -> None:
        """Bootstrap VM with Tailscale and SSH.

        Note: BoxLite exec calls don't persist state between invocations,
        so we combine all bootstrap steps into a single script.
        """
        run = box.exec  # type: ignore[attr-defined]

        oauth_secret = CONFIG.tailscale.oauth_secret
        if not oauth_secret:
            raise ValueError("Tailscale OAuth secret required. Set OCAPTAIN_TAILSCALE_OAUTH_SECRET")

        ship_tag = CONFIG.tailscale.ship_tag
        auth_key = f"{oauth_secret}?ephemeral=true&preauthorized=true"
        _, public_key = get_ssh_keypair()

        logger.info("Bootstrapping VM %s (tag: %s)", name, ship_tag)

        # Run entire bootstrap as a single script since BoxLite doesn't persist state
        result = await run(
            "bash",
            "-c",
            f"""
            set -e

            # Install essentials (including tmux/expect needed for Claude sessions)
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                openssh-server curl sudo git tmux expect

            # Install GitHub CLI
            GH_KEYRING=/usr/share/keyrings/githubcli-archive-keyring.gpg
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | dd of=$GH_KEYRING
            chmod go+r $GH_KEYRING
            echo "deb [arch=$(dpkg --print-architecture) signed-by=$GH_KEYRING] \
                https://cli.github.com/packages stable main" \
                | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y gh

            # Start sshd on port 2222 (ocaptain standard)
            mkdir -p /run/sshd
            echo 'Port 2222' > /etc/ssh/sshd_config.d/ocaptain.conf
            /usr/sbin/sshd

            # Create ubuntu user and setup SSH
            id ubuntu || useradd -m -s /bin/bash ubuntu
            echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
            mkdir -p /home/ubuntu/.ssh
            echo {shlex.quote(public_key.strip())} >> /home/ubuntu/.ssh/authorized_keys
            chown -R ubuntu:ubuntu /home/ubuntu/.ssh
            chmod 700 /home/ubuntu/.ssh
            chmod 600 /home/ubuntu/.ssh/authorized_keys

            # Install Tailscale
            curl -fsSL https://tailscale.com/install.sh | sh

            # Create required directories for tailscaled (no systemd in container images)
            mkdir -p /run/tailscale
            mkdir -p /var/lib/tailscale
            mkdir -p /var/cache/tailscale
            chmod 0755 /run/tailscale
            chmod 0700 /var/lib/tailscale
            chmod 0750 /var/cache/tailscale

            # Start tailscaled manually with ephemeral state
            # NOTE: Must use subshell + stdio redirect for BoxLite - plain & causes exec
            # to hang because BoxLite waits for all file descriptors to close
            TS_SOCK=/run/tailscale/tailscaled.sock
            (/usr/sbin/tailscaled --state=mem: --socket=$TS_SOCK \
                --tun=userspace-networking </dev/null >/var/log/tailscaled.log 2>&1 &)
            sleep 5  # Give tailscaled time to initialize

            # Verify tailscaled is running
            if ! pgrep -x tailscaled > /dev/null; then
                echo 'tailscaled failed to start'
                exit 1
            fi
            echo 'tailscaled is running'

            # Join tailnet
            /usr/bin/tailscale --socket=$TS_SOCK up \
                --authkey={shlex.quote(auth_key)} \
                --hostname={shlex.quote(name)} \
                --advertise-tags={shlex.quote(ship_tag)}

            # Wait for Tailscale networking to stabilize
            echo 'Waiting for Tailscale to stabilize...'
            sleep 10

            # Verify sshd is running on port 2222
            if ! pgrep -x sshd > /dev/null; then
                echo 'sshd not running, restarting...'
                /usr/sbin/sshd
                sleep 1
            fi
            echo 'sshd status:'
            ss -tlnp | grep ':2222' || echo 'Warning: port 2222 not listening'

            # Verify Tailscale is connected
            echo 'Tailscale status:'
            /usr/bin/tailscale --socket=$TS_SOCK status 2>&1 | head -5

            # Install Claude Code
            curl -fsSL https://claude.ai/install.sh | bash

            echo 'Bootstrap complete'
            """,
        )
        logger.info("Bootstrap output for %s: %s", name, result.stdout[-500:])

    def destroy(self, vm_id: str) -> None:
        """Destroy a BoxLite VM."""
        if vm_id not in self._boxes:
            return
        self._loop.run_until_complete(self._destroy(vm_id))

    async def _destroy(self, vm_id: str) -> None:
        """Async implementation of destroy."""
        box = self._boxes[vm_id]
        run = box.exec  # type: ignore[attr-defined]

        try:
            await run(
                "bash", "-c", "/usr/bin/tailscale --socket=/run/tailscale/tailscaled.sock logout"
            )
        except Exception as e:
            logger.warning("Failed to logout from Tailscale during VM %s destruction: %s", vm_id, e)

        await box.__aexit__(None, None, None)  # type: ignore[attr-defined]
        del self._boxes[vm_id]
        del self._vms[vm_id]

    def get(self, vm_id: str) -> VM | None:
        """Get VM by ID."""
        return self._vms.get(vm_id)

    def list(self, prefix: str | None = None) -> list[VM]:
        """List VMs, optionally filtered by name prefix."""
        vms = self._vms.values()
        if prefix:
            return [v for v in vms if v.name.startswith(prefix)]
        return list(vms)

    def wait_ready(self, vm: VM, timeout: int = 300) -> bool:
        """Wait for VM to be SSH-accessible via Tailscale."""
        from pathlib import Path

        from ..config import get_ssh_keypair

        get_ssh_keypair()  # Ensure key exists
        private_key_path = str(Path.home() / ".config" / "ocaptain" / "id_ed25519")

        # BoxLite runs sshd on port 2222 (ocaptain standard)
        connect_kwargs = {
            "key_filename": private_key_path,
            "look_for_keys": False,
        }

        start = time.time()
        while time.time() - start < timeout:
            try:
                with Connection(
                    vm.ssh_dest,
                    port=2222,
                    connect_timeout=10,
                    connect_kwargs=connect_kwargs,
                ) as c:
                    c.run("echo ready", hide=True)
                return True
            except KeyboardInterrupt:
                raise
            except Exception as e:
                logger.debug("SSH not ready for %s: %s", vm.name, e)
                time.sleep(3)
        return False
