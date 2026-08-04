# Kaappi's patches to isocline

Vendored from <https://github.com/daanx/isocline> at commit
`8d6dc1ef95b1b46711e66eb23d39d4467a0fcdac` (2026-04-23, v1.1.0), MIT licensed —
see `LICENSE`.

**This is a patched copy.** Two changes diverge from upstream. Both are marked
in the source with a `KAAPPI PATCH <n>` comment pointing here. When updating
isocline, re-apply them; `grep -rn 'KAAPPI PATCH' vendor/isocline/` finds every
site.

## Patch 1 — an input-completeness callback

**Files:** `include/isocline.h`, `src/env.h`, `src/isocline.c`,
`src/editline.c`

Upstream decides at Enter that input is finished unless it ends in the
`multiline_eol` continuation character (`\`); a newline is otherwise entered
explicitly with shift-tab or ctrl-J. That is right for a shell and wrong for a
Lisp prompt, where whether the form is finished is a property of the text, not
of which key was pressed.

The patch adds:

```c
typedef bool (ic_is_complete_fun_t)(const char* input, void* arg);
void ic_set_default_is_complete(ic_is_complete_fun_t* is_complete, void* arg);
```

When set, and multi-line editing is enabled, Enter consults it: `true` submits,
`false` inserts a newline and keeps editing. With no callback set, behavior is
exactly upstream's.

Kaappi answers it from the reader (`repl.inputIncomplete` → the reader's
`incomplete_input` mode), so the prompt and the file loader agree about where a
datum ends.

## Patch 2 — configurable history size

**File:** `src/history.c`

Upstream clamps every history to `IC_MAX_HISTORY` (200) regardless of what the
caller asks for. Kaappi's `repl.history-length` defaults to 1000 and is user
configurable (`src/config.zig`), so an explicit request has to be honored.

`IC_MAX_HISTORY` is now a sanity bound (1000000) and `IC_DEFAULT_HISTORY` (200,
upstream's value) applies when the caller passes a negative count. A caller
asking for 1000 gets 1000.

## Deliberately not patched

**No assume-TTY test hook.** The linenoise fork this replaced carried
`LINENOISE_ASSUME_TTY` so tests could drive it without a terminal. Nothing
outside `vendor/` ever set it. REPL tests use a real pty instead, which
exercises the terminal path rather than bypassing it.
