# Cubeage Solar2D IronSource Plugin

Cubeage Solar2D IronSource Plugin is the self-hosted native Solar2D plugin for IronSource/Unity LevelPlay. It owns the Android and iOS native plugin source, packaging workflows, and GitHub Release artifacts consumed by Solar2D applications.

Lifecycle: `production`
Layer: `foundation`

## Goals

- Maintain the Solar2D `plugin.ironSource` native integration for Android and iOS.
- Package Android and iOS release artifacts that Solar2D apps can consume from GitHub Releases.
- Keep IronSource SDK versioning, Solar2D metadata, and platform requirements explicit.

## Non-Goals

- This repository does not own game-specific ad placement policy, monetization strategy, or app runtime behavior.
- This repository does not own the upstream IronSource SDK or Solar2D runtime.
- This repository does not own central CI runner, enterprise release bot, or platform preview behavior.

## Boundaries

The machine-readable source of truth is [.doctrine/project.json](.doctrine/project.json). Agents must keep this repository as a reusable native plugin package and route app-specific ad behavior to consuming game repositories.

## Public Surfaces

- Lua plugin API documented in `README.md`.
- Android native plugin code under `android/`.
- iOS native plugin code under `ios/`.
- Solar2D plugin metadata in `metadata.lua`.
- GitHub Release artifacts `android.tgz` and `iphone.tgz` produced by `.github/workflows/release.yml`.

## Delivery

Release changes require Android and iOS build artifacts, package smoke evidence, GitHub Release readback, and consumer compatibility notes for affected apps. Published artifacts are externally consumable; recovery is normally a forward-fix release, release deletion/deprecation when safe, or staged channel halt rather than source revert alone.
