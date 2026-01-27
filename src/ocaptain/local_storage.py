"""Local storage management for voyages."""

from pathlib import Path

from . import config


def get_voyage_dir(voyage_id: str) -> Path:
    """Get local voyage directory path."""
    workspace = Path(config.CONFIG.local.workspace_dir).expanduser()
    return workspace / voyage_id


def setup_local_voyage(voyage_id: str, task_list_id: str) -> Path:
    """Set up local directory structure for a voyage.

    Returns the voyage directory path.
    """
    voyage_dir = get_voyage_dir(voyage_id)

    # Create directory structure
    (voyage_dir / "workspace").mkdir(parents=True, exist_ok=True)
    (voyage_dir / "artifacts").mkdir(exist_ok=True)
    (voyage_dir / "logs").mkdir(exist_ok=True)
    (voyage_dir / ".claude" / "tasks" / task_list_id).mkdir(parents=True, exist_ok=True)

    return voyage_dir
