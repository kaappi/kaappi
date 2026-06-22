# Ecosystem Library Bar

Every `kaappi-*` package should meet the following quality bar before being
advertised as production-ready:

## Required

1. **CI** — GitHub Actions workflow that builds the C side (if any) and runs
   the Scheme test suite against the matching interpreter version.

2. **Tests** — At minimum, a smoke test that imports the library and exercises
   one call per exported procedure. Network/DB clients need integration tests
   against containerized services (Redis, Postgres) in CI.

3. **No committed build artifacts** — `.dylib` and `.so` files must be in
   `.gitignore`. `make` or the package `build:` step produces them.

4. **`kaappi.pkg` manifest** — declares `name`, `depends`, and `build`.

5. **Interpreter version** — Either the `kaappi.pkg` or the CI matrix declares
   which Kaappi version(s) the library is tested against.

6. **README** — What the library does, how to install, basic usage example.

## FFI signature compatibility

Libraries with C FFI code (`kaappi-net`, `kaappi-redis`, `kaappi-pg`,
`kaappi-http`) depend on specific FFI type signatures matching the interpreter's
dispatch tables in `src/ffi.zig`.

When `ffi.zig` changes, verify ecosystem libraries still work by running their
test suites. The interpreter's unit tests cover FFI type marshaling, but
end-to-end coverage with real libraries catches dispatch-table drift.

## Committed artifact cleanup

The following `kaappi-*` repos have been identified as having committed
`.dylib`/`.so` files that should be removed and `.gitignore`d:

- `kaappi-http` — `libkaappi_http.dylib`

When cleaning these up:
1. Add `*.dylib` and `*.so` to `.gitignore`
2. `git rm --cached` the artifact
3. Ensure `make` rebuilds it
