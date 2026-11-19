<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Versioning

The manifest and the git tag record the version; the deck exports no version
constant.

## deck.toml is authored

`package.version` is committed by hand. `jvc` resolves a deck against the
manifest **on the default branch**: it reads `package.urls.deck`, which points
at `raw.githubusercontent.com/.../main/deck.toml`. A version that only ever
existed inside a CI workspace would leave `jvc` resolving whatever was last
committed.

So bump `deck.toml`, commit, then tag to match. `release.yml` refuses a tag
that disagrees with the manifest.

Only plain `N.N.N` tags are releases. `release.yml` rejects a tag with a `v`
prefix or a prerelease suffix (`0.2.0-rc1`).

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
