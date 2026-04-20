---
title: Profile Template Bundle
description: Versioned baseline bundle for seeding hardened user-project profiles from the code-server profile.
owner: platform
last_review_date: 2026-04-19
status: active
related_issues:
  - 899
---

# Profile Template Bundle

## Purpose

This bundle defines the hardened baseline that should be copied into a new project profile when a project is created from the code-server profile.

## Bundle Contract

The canonical bundle is stored at [config/profile-template-bundles/hardened-baseline-v1.json](../../config/profile-template-bundles/hardened-baseline-v1.json).

The bundle contains:

- Immutable baseline settings.
- Inherited CI checks for secrets scan, lint, test, and SAST coverage.
- Starter documentation and SSOT links.
- A tracked exception policy reference.

## Safe Propagation

When the bundle version changes, the seeding helper re-materializes the profile namespace and refreshes the bundle manifest.

This avoids drift between the versioned bundle and the actual project profile files.

## Exception Flow

Exceptions must be:

1. Tracked in a GitHub issue.
2. Approved before the seeded baseline is modified.
3. Recorded in the profile bundle manifest.

## Implementation

- Bundle loading and checksuming live in [src/services/tenant-profile-manager/template-bundles.ts](../../src/services/tenant-profile-manager/template-bundles.ts).
- Profile seeding and sync live in [src/services/tenant-profile-manager/index.ts](../../src/services/tenant-profile-manager/index.ts).

## Operational Use

Provisioning automation should call the profile manager seeding method before a new project is exposed to a user.

That guarantees the project starts with the hardened baseline instead of inheriting a blank or partially configured profile.
