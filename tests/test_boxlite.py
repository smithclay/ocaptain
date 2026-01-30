"""Tests for BoxLite provider implementation."""

from unittest.mock import MagicMock, patch


def test_boxlite_provider_registered() -> None:
    """BoxLiteProvider should register with name 'boxlite'."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.provider import _PROVIDERS

        # Import triggers registration
        from ocaptain.providers import boxlite  # noqa: F401

        assert "boxlite" in _PROVIDERS


def test_boxlite_provider_list_empty() -> None:
    """list() should return empty list when no VMs exist."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        assert provider.list() == []


def test_boxlite_provider_list_with_prefix() -> None:
    """list() should filter by prefix when provided."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.provider import VM, VMStatus
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        # Manually add VMs to internal state
        provider._vms["voyage-abc-ship0"] = VM(
            id="voyage-abc-ship0",
            name="voyage-abc-ship0",
            ssh_dest="ubuntu@100.64.1.1",
            status=VMStatus.RUNNING,
        )
        provider._vms["voyage-xyz-ship0"] = VM(
            id="voyage-xyz-ship0",
            name="voyage-xyz-ship0",
            ssh_dest="ubuntu@100.64.1.2",
            status=VMStatus.RUNNING,
        )

        result = provider.list(prefix="voyage-abc")
        assert len(result) == 1
        assert result[0].name == "voyage-abc-ship0"


def test_boxlite_provider_get_returns_none_when_not_found() -> None:
    """get() should return None when VM doesn't exist."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        assert provider.get("nonexistent") is None


def test_boxlite_provider_get_returns_vm_when_found() -> None:
    """get() should return VM when it exists."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.provider import VM, VMStatus
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        vm = VM(
            id="test-vm",
            name="test-vm",
            ssh_dest="ubuntu@100.64.1.1",
            status=VMStatus.RUNNING,
        )
        provider._vms["test-vm"] = vm

        assert provider.get("test-vm") == vm


def test_boxlite_provider_wait_ready_success() -> None:
    """wait_ready() should return True when SSH is accessible."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.provider import VM, VMStatus
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        vm = VM(
            id="test-vm",
            name="test-vm",
            ssh_dest="ubuntu@100.64.1.1",
            status=VMStatus.RUNNING,
        )

        with patch("ocaptain.providers.boxlite.Connection") as mock_conn:
            mock_connection = MagicMock()
            mock_conn.return_value.__enter__ = MagicMock(return_value=mock_connection)
            mock_conn.return_value.__exit__ = MagicMock(return_value=False)
            mock_connection.run.return_value = MagicMock(stdout="ready")

            assert provider.wait_ready(vm, timeout=5) is True


def test_boxlite_provider_wait_ready_timeout() -> None:
    """wait_ready() should return False on timeout."""
    with patch.dict("sys.modules", {"boxlite": MagicMock()}):
        from ocaptain.provider import VM, VMStatus
        from ocaptain.providers.boxlite import BoxLiteProvider

        provider = BoxLiteProvider()
        vm = VM(
            id="test-vm",
            name="test-vm",
            ssh_dest="ubuntu@100.64.1.1",
            status=VMStatus.RUNNING,
        )

        with patch("ocaptain.providers.boxlite.Connection") as mock_conn:
            mock_conn.return_value.__enter__ = MagicMock(
                side_effect=Exception("Connection refused")
            )

            # Use very short timeout for test speed
            with patch("time.sleep"):  # Skip actual sleeping
                assert provider.wait_ready(vm, timeout=1) is False
