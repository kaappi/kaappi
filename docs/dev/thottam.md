# thottam — the package manager

`src/thottam.zig` is a second Zig binary that installs Kaappi ecosystem
libraries. It is built alongside `kaappi` by `zig build` and ships in the
release artifacts for every platform.

## Commands

```bash
thottam install kaappi-web                                       # from default org
thottam install kaappi-auth::https://github.com/bob/kaappi-auth  # from custom URL
thottam install kaappi-web@v1.0.0                                # pinned version
thottam install kaappi-net@">=0.2.0"                             # semver constraint
thottam list                                                     # show installed packages
thottam update                                                   # pull + rebuild all
thottam remove kaappi-web                                        # uninstall
```

## How it works

- Clones from `github.com/kaappi/<package>` (or a custom `::url`) into
  `$KAAPPI_HOME/src/` (`~/.kaappi/src/` by default).
- Reads `kaappi.pkg` for the package name, dependencies, build command, and
  declared source.
- Copies `.sld` files to `~/.kaappi/lib/`, preserving directory structure.
- Copies `.dylib`/`.so` to `~/.kaappi/lib/`.
- Records source URLs in the lockfile `~/.kaappi/thottam.lock`, for provenance.
- Records each installed file in `~/.kaappi/thottam.files`, so `remove` only
  unlinks files no other installed package still needs (kaappi#2136). When an
  install or update copies a file another package already owns, thottam
  warns; the newest copy stays authoritative, and removing the package that
  last copied it does not restore the earlier package's copy.

**Auto-discovery.** `main.zig` automatically adds the script's own directory and
`~/.kaappi/lib` to the library search path, after any `--lib-path` entries — so a
program can import libraries that live next to it regardless of the working
directory. `ffi-open` also searches `~/.kaappi/lib/` for native libraries. No
`--lib-path` or `DYLD_LIBRARY_PATH` is needed after an install.

Note that `~/.kaappi/lib` is deliberately **not** on `kaappi compile`'s
`libkaappi_rt.a` search path — it is thottam's Scheme-library and FFI-`dlopen`
directory. See the LLVM backend section of `CLAUDE.md`.

## The `kaappi.pkg` manifest

```text
name: kaappi-web
depends: kaappi-http kaappi-json
build: make
source: https://github.com/someone/kaappi-web
```

Four keys are read: `name:`, `depends:`, `build:`, and `source:`. There is no
`version:` field — thottam locks by git SHA, so a version written in the
manifest would mean nothing; it is dropped like any unknown key (kaappi#2138).

- `name`, when present, must match the package being installed. A manifest that
  names a different package is a packaging error, and the install refuses
  before recording anything (removing the checkout it just cloned, so nothing
  unrecorded is left for a later install to reuse). It is optional — a manifest
  may omit it — but a mismatching `name:` is never accepted. The check is scoped
  to unlocked installs: in `--locked` mode the lockfile already vouches for the
  exact SHA, so the manifest at that SHA is not re-litigated.
- `source` declares where the package is canonically hosted. On a bare-name
  install (no `::url` on the command line) it is recorded as the lockfile's
  provenance, so `thottam list` shows `(from: …)` and a later `--locked`
  install fetches from it — surfaced with a one-line note at record time, since
  the manifest is then steering where the package comes from. It **cannot**
  redirect the *first* clone: thottam can only read the manifest after cloning
  the repo, so the initial fetch URL is always the `::url` given on the command
  line or the `KAAPPI_ORG` default. When a `::url` *is* given and disagrees with
  `source:`, thottam warns (a fork or mirror is legitimate) and records the URL
  it actually fetched from, never the manifest's claim. The comparison ignores a
  trailing `/` and a `.git` suffix — those are cosmetic spellings of one
  remote — but a scheme difference (`http` vs `https`) is a real downgrade and
  still warns. In `--locked` mode the lockfile is authoritative and the
  manifest's `source:` is ignored (#2137).
- `depends` is space-separated, and may carry an inline custom URL:
  `depends: kaappi-net kaappi-auth::https://github.com/bob/kaappi-auth`.
- Version constraints use `>=`, `>`, `<=`, `<`, `^` (compatible), `~`
  (patch-level), and comma-separated ranges (`>=1.0.0,<2.0.0`):
  `depends: kaappi-net@">=0.2.0"`. Constraints resolve against git tags via
  `git ls-remote --tags`.

  `^` and `~` follow node-semver's range grammar, including its abbreviated
  forms: `^1` is `>=1.0.0 <2.0.0`, `~1` is likewise `>=1.0.0 <2.0.0` (not
  `~1.0.0`'s `>=1.0.0 <1.1.0`), and `^0.0` is the whole `0.0.x` line.
  Whitespace between an operator and its version is accepted (`>= 1.0.0`).

  A git tag only counts as a release candidate if it is a valid SemVer
  2.0.0 version: one to three numeric components, digits only, no leading
  zeroes (`v1` and `v1.2` are accepted, filling omitted components with 0;
  a fourth component is not a version). A tag like
  `v2.0.0.nightly-UNRELEASED` or `v1_0.0.0` is not a version and is ignored,
  never outranking a real release.
- `build` runs only if the package has native code (conventionally a `csrc/`
  directory with a `Makefile` in the repo root). An empty `build:` line is
  treated as absent.

## Ecosystem library layout

Every `kaappi-*` package follows the same shape:

- `csrc/` — C helper for FFI (if needed)
- `lib/kaappi/<name>.sld` — main library with re-exports
- `lib/kaappi/<name>/` — sub-libraries (`ffi.sld`, `parse.sld`, …)
- `kaappi.pkg` — package manifest
- `Makefile` — builds the `.dylib`/`.so` (if there is C code)

All FFI signatures must match entries in this repo's `src/ffi.zig` dispatch
tables.

The core set, for orientation:

| Package | Type | Dependencies | Purpose |
|---------|------|-------------|---------|
| kaappi-net | C + Scheme | OpenSSL | TCP client/server, TLS client |
| kaappi-json | Pure Scheme | none | JSON parser/serializer |
| kaappi-redis | C + Scheme | kaappi-net | Redis client (RESP2) |
| kaappi-pg | C + Scheme | libpq | PostgreSQL client (DB-API 2.0) |
| kaappi-http | Scheme | kaappi-net | HTTP/HTTPS client + server |
| kaappi-web | Pure Scheme | kaappi-http, kaappi-json | Web framework (routing, middleware) |

The workspace-level `CLAUDE.md` (one directory up from this repo) has the full
ecosystem table, the nightly-CI grouping, and the per-repo bar
(`docs/dev/ecosystem-library-bar.md`).
