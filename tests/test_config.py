"""Tests for ocaptain configuration."""

import pytest

from ocaptain.config import OcaptainConfig, load_config


def test_config_has_tailscale_section() -> None:
    """Config should have tailscale section with oauth_secret and ip."""
    config = OcaptainConfig()
    assert hasattr(config, "tailscale")
    assert config.tailscale.oauth_secret is None
    assert config.tailscale.ip is None
    assert config.tailscale.ship_tag == "tag:ocaptain-ship"


def test_config_has_local_section() -> None:
    """Config should have local storage section."""
    config = OcaptainConfig()
    assert hasattr(config, "local")
    assert "voyages" in config.local.workspace_dir


def test_tailscale_oauth_secret_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Tailscale OAuth secret should load from environment."""
    monkeypatch.setenv("OCAPTAIN_TAILSCALE_OAUTH_SECRET", "tskey-client-xxx-yyy")
    config = load_config()
    assert config.tailscale.oauth_secret == "tskey-client-xxx-yyy"
