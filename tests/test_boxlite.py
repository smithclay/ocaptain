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
