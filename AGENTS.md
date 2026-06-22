# Repository Instructions

Follow the enterprise doctrine in `SylphxAI/doctrine` and the local project boundary in [PROJECT.md](PROJECT.md). The machine-readable control-plane manifest is [.doctrine/project.json](.doctrine/project.json).

This repository owns the reusable Solar2D IronSource native plugin package only. Do not add game-specific ad placement policy, monetization behavior, central CI, release-bot, or platform-preview behavior here.

For package changes, record Android and iOS build evidence, release artifact readback, and consumer compatibility impact. Published artifacts are forward-fix recovery unless a repo-local release runbook proves a safer rollback.
