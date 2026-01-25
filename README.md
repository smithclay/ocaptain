# ocaptain

[![Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![exe.dev](https://img.shields.io/badge/Powered%20by-exe.dev-orange.svg)](https://exe.dev)

> O Captain! my Captain! our fearful Claude Code session is done, The repo has weather’d every rack, the prize we sought is won.

Minimalist multi-coding agent control plane built on top of [exe.dev](https://exe.dev) VMs.  Orchestration uses Claude Code's new [task list](https://x.com/trq212/status/2014480496013803643?s=20) orchestration: tasks are distributed among multiple, full-featured Linux VMs that can coordinate work in parallel.

Inspired by Steve Yegge's [Gas Town](https://github.com/steveyegge/gastown), this is going to be one of approximately 40,000 coding agent orchestration tools in 2026. Spiritual successor to [claudetainer](https://github.com/smithclay/claudetainer).

## Quick start

```bash
uv run ocaptain sail "Update the README to Hello World (from Claude Code)" --repo octocat/Hello-World --ships 1
```
