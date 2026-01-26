"""Tests for local storage module."""

from pathlib import Path

import pytest


def test_get_voyage_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """get_voyage_dir should return correct path."""
    # Patch config to use tmp_path
    from ocaptain import config
    from ocaptain.local_storage import get_voyage_dir

    monkeypatch.setattr(
        config,
        "CONFIG",
        config.OcaptainConfig(local=config.LocalStorageConfig(workspace_dir=str(tmp_path))),
    )

    voyage_dir = get_voyage_dir("voyage-abc123")
    assert voyage_dir == tmp_path / "voyage-abc123"


def test_setup_local_voyage(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """setup_local_voyage should create directory structure."""
    from ocaptain import config
    from ocaptain.local_storage import setup_local_voyage

    monkeypatch.setattr(
        config,
        "CONFIG",
        config.OcaptainConfig(local=config.LocalStorageConfig(workspace_dir=str(tmp_path))),
    )

    voyage_dir = setup_local_voyage("voyage-abc123", "task-list-id")

    assert voyage_dir.exists()
    assert (voyage_dir / "workspace").exists()
    assert (voyage_dir / "artifacts").exists()
    assert (voyage_dir / "logs").exists()
    assert (voyage_dir / ".claude" / "tasks" / "task-list-id").exists()
