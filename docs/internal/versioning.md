<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Versioning

The git tag is the source of truth. Two places record a version.

## deck.toml is authored

`package.version` is committed by hand. `jvc` resolves a deck against the
manifest **on the default branch**: it reads `package.urls.deck`, which points
at `raw.githubusercontent.com/.../main/deck.toml`. A version that only ever
existed inside a CI workspace would leave `jvc` resolving whatever was last
committed.

So bump `deck.toml`, commit, then tag to match. `release.yml` refuses a tag
that disagrees with the manifest.

## src/topics/version.j is generated

`geo.VERSION` says which build this is. `tools/inject-version.sh` stamps it
from what `tools/version.sh` derives:

| HEAD | `VERSION` |
|---|---|
| a stable tag | `0.2.0` |
| anywhere else | `0.2.0-dev+14.9ebf3dd` |
| nothing tagged yet | `<manifest version>-dev+<commits>.<sha>` |
| no git checkout | whatever the manifest declares |

Only plain `N.N.N` tags anchor a release. A tag with a `v` prefix or a
prerelease suffix (`0.2.0-rc1`) is not a release: `tools/version.sh` does not
anchor on one and `release.yml` rejects it.

The dev form matches what `jennifer version` prints. Semver precedence ignores
build metadata after `+`, so `0.2.0-dev+14.9ebf3dd` orders before `0.2.0`.

CI injects the version before `fmt` and the header guard, since injection
generates a `.j` file that both check.

## Cutting a release

```sh
# 1. bump the manifest and commit it
$EDITOR deck.toml
git commit -am "release 0.2.0"

# 2. tag to match, and push
git tag 0.2.0
git push origin main 0.2.0
```

`release.yml` runs the whole gate again, builds the archive with
`tools/pack.sh`, and creates the GitHub release.
