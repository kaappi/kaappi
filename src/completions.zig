//! Shell completion scripts for `kaappi` and `thottam`, generated at comptime
//! from `cli_spec.zig` — the same tables the argument parsers dispatch on.
//!
//! Nothing here is hand-maintained. Add a flag to a table in `cli_spec.zig`
//! and all six scripts grow it; there is no second list to forget. See that
//! file's header for the drift this replaced.
//!
//! Three properties the generators preserve, in order of how badly a user
//! feels their absence:
//!
//!  1. **Soundness** — never offer something the parser rejects. The five
//!     subcommands that intercept argv in their own module (`explain`,
//!     `features`, `test`, `doctor`, `cache`) reject every global flag with
//!     exit 2, so their completions are scoped to their own table. The zsh and
//!     fish scripts previously offered all 21 global flags inside each of them.
//!  2. **Completeness** — every flag a parser accepts is offered somewhere.
//!  3. **Value completion** — a flag that takes a path completes paths, and
//!     one that takes a fixed set completes that set.

const std = @import("std");
const spec = @import("cli_spec.zig");

const ShellFlag = spec.ShellFlag;
const SubcommandDesc = spec.SubcommandDesc;

// ── Shared comptime helpers ────────────────────────────────────────────

/// The words a shell should offer for `f` when the user is typing a flag.
/// An `.inline_eq` flag is only ever legal with its value attached, so the
/// offered words are the full `--flag=value` spellings; an optional-value one
/// offers the bare spelling too.
fn flagWords(comptime f: ShellFlag) []const []const u8 {
    comptime {
        var out: []const []const u8 = &.{};
        switch (f.value) {
            .none, .separate => {
                out = out ++ [_][]const u8{f.long};
                if (f.short) |s| out = out ++ [_][]const u8{s};
            },
            .inline_eq => {
                for (f.choices) |c| out = out ++ [_][]const u8{f.long ++ "=" ++ c};
            },
            .inline_eq_optional => {
                out = out ++ [_][]const u8{f.long};
                for (f.choices) |c| out = out ++ [_][]const u8{f.long ++ "=" ++ c};
            },
        }
        return out;
    }
}

fn joinWords(comptime words: []const []const u8) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (words, 0..) |w, i| {
            if (i > 0) s = s ++ " ";
            s = s ++ w;
        }
        return s;
    }
}

fn wordsFor(comptime flags: []const ShellFlag) []const []const u8 {
    comptime {
        var out: []const []const u8 = &.{};
        for (flags) |f| out = out ++ flagWords(f);
        return out;
    }
}

fn withoutOverlap(comptime all: []const ShellFlag, comptime remove: []const ShellFlag) []const ShellFlag {
    comptime {
        var out: []const ShellFlag = &.{};
        next: for (all) |f| {
            for (remove) |g| {
                if (std.mem.eql(u8, f.long, g.long)) continue :next;
            }
            out = out ++ [_]ShellFlag{f};
        }
        return out;
    }
}

fn hasFlag(comptime flags: []const ShellFlag, comptime f: ShellFlag) bool {
    comptime {
        for (flags) |g| {
            if (std.mem.eql(u8, g.long, f.long)) return true;
        }
        return false;
    }
}

/// Every flag in every kaappi table, deduplicated by spelling. The bash `case
/// "$prev"` value arms are built from this, so a flag that takes a path
/// completes paths no matter which subcommand it belongs to.
fn allKaappiFlags() []const ShellFlag {
    comptime {
        var out: []const ShellFlag = spec.erase(spec.GlobalId, &spec.global_flags);
        for (spec.subcommands) |s| {
            next: for (s.flags) |f| {
                for (out) |seen| {
                    if (std.mem.eql(u8, seen.long, f.long)) continue :next;
                }
                out = out ++ [_]ShellFlag{f};
            }
        }
        return out;
    }
}

/// The `|`-joined bash `case` pattern for every separate-value flag of one
/// `ValueKind`. Empty when nothing has that kind — an empty pattern would be
/// a syntax error, so callers must not emit the arm.
fn caseArmPattern(comptime flags: []const ShellFlag, comptime kind: spec.ValueKind) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (flags) |f| {
            if (f.value != .separate or f.kind != kind) continue;
            if (s.len > 0) s = s ++ "|";
            s = s ++ f.long;
            if (f.short) |sh| s = s ++ "|" ++ sh;
        }
        return s;
    }
}

fn choiceValueArms(comptime flags: []const ShellFlag) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (flags) |f| {
            if (f.value != .separate or f.kind != .choice) continue;
            s = s ++ "        " ++ f.long;
            if (f.short) |sh| s = s ++ "|" ++ sh;
            s = s ++ ")\n            COMPREPLY=($(compgen -W \"" ++ joinWords(f.choices) ++
                "\" -- \"$cur\"))\n            return ;;\n";
        }
        return s;
    }
}

fn subcommandNames(comptime subs: []const SubcommandDesc, comptime sep: []const u8) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (subs, 0..) |sub, i| {
            if (i > 0) s = s ++ sep;
            s = s ++ sub.name;
        }
        return s;
    }
}

/// The top-level flags: every global flag marked `top_level`. `--no-opt` and
/// `--check` are excluded here and offered under `ir` / `fmt` instead.
fn kaappiTopFlags() []const ShellFlag {
    comptime {
        var out: []const ShellFlag = &.{};
        for (spec.erase(spec.GlobalId, &spec.global_flags)) |f| {
            if (f.top_level) out = out ++ [_]ShellFlag{f};
        }
        return out;
    }
}

// ── bash ───────────────────────────────────────────────────────────────

fn bashPositional(comptime pos: spec.Positional, comptime choices: []const []const u8) []const u8 {
    return switch (pos) {
        .none, .opaque_word => "",
        .scm_file => "$(compgen -f -X '!*.scm' -- \"$cur\")",
        .path => "$(compgen -f -- \"$cur\")",
        .choice => "$(compgen -W \"" ++ joinWords(choices) ++ "\" -- \"$cur\")",
    };
}

fn bashScript(
    comptime cmd: []const u8,
    comptime top_flags: []const ShellFlag,
    comptime subs: []const SubcommandDesc,
    comptime all_flags: []const ShellFlag,
    comptime top_positional: spec.Positional,
) []const u8 {
    comptime {
        @setEvalBranchQuota(2_000_000);
        var s: []const u8 = "";
        s = s ++ "# bash completion for " ++ cmd ++ " - generated from src/cli_spec.zig, do not edit\n";
        s = s ++ "_" ++ cmd ++ "() {\n";
        s = s ++ "    local cur prev sub word\n";
        s = s ++ "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n";
        s = s ++ "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n\n";

        // 1. The previous word is a flag expecting a separate value.
        s = s ++ "    case \"$prev\" in\n";
        s = s ++ choiceValueArms(all_flags);
        const dirs = caseArmPattern(all_flags, .dir);
        if (dirs.len > 0) {
            s = s ++ "        " ++ dirs ++ ")\n            COMPREPLY=($(compgen -d -- \"$cur\"))\n            return ;;\n";
        }
        const files = caseArmPattern(all_flags, .file);
        if (files.len > 0) {
            s = s ++ "        " ++ files ++ ")\n            COMPREPLY=($(compgen -f -- \"$cur\"))\n            return ;;\n";
        }
        // A value with nothing to complete (a millisecond count, a git rev):
        // offering files there is worse than offering nothing.
        const opaque_vals = caseArmPattern(all_flags, .none);
        if (opaque_vals.len > 0) {
            s = s ++ "        " ++ opaque_vals ++ ")\n            return ;;\n";
        }
        s = s ++ "    esac\n\n";

        // 2. Which subcommand is in play? Scan only the words already typed,
        //    so a half-typed "$cur" is never mistaken for one.
        if (subs.len > 0) {
            s = s ++ "    sub=\"\"\n";
            s = s ++ "    for word in \"${COMP_WORDS[@]:1:$(( COMP_CWORD > 1 ? COMP_CWORD-1 : 0 ))}\"; do\n";
            s = s ++ "        case \"$word\" in\n";
            s = s ++ "            " ++ subcommandNames(subs, "|") ++ ") sub=\"$word\"; break ;;\n";
            s = s ++ "        esac\n";
            s = s ++ "    done\n\n";

            s = s ++ "    case \"$sub\" in\n";
            for (subs) |sub| {
                s = s ++ "        " ++ sub.name ++ ")\n";
                // A subcommand cli.parse handles inline goes through the same
                // global loop, so every top-level flag is legal there too.
                const extra: []const ShellFlag = if (sub.global_flags_ok)
                    withoutOverlap(top_flags, sub.flags)
                else
                    &.{};
                const words = wordsFor(sub.flags) ++ wordsFor(extra);
                if (words.len > 0) {
                    s = s ++ "            if [[ \"$cur\" == -* ]]; then\n";
                    s = s ++ "                COMPREPLY=($(compgen -W \"" ++ joinWords(words) ++ "\" -- \"$cur\"))\n";
                    s = s ++ "                return\n";
                    s = s ++ "            fi\n";
                }
                const pos = bashPositional(sub.positional, sub.choices);
                if (pos.len > 0) s = s ++ "            COMPREPLY=(" ++ pos ++ ")\n";
                s = s ++ "            return ;;\n";
            }
            s = s ++ "    esac\n\n";
        }

        // 3. No subcommand yet.
        const top_words = wordsFor(top_flags);
        if (top_words.len > 0) {
            s = s ++ "    if [[ \"$cur\" == -* ]]; then\n";
            s = s ++ "        COMPREPLY=($(compgen -W \"" ++ joinWords(top_words) ++ "\" -- \"$cur\"))\n";
            s = s ++ "        return\n";
            s = s ++ "    fi\n\n";
        }
        var tail: []const u8 = "";
        if (subs.len > 0) {
            tail = tail ++ "$(compgen -W \"" ++ subcommandNames(subs, " ") ++ "\" -- \"$cur\")";
        }
        const top_pos = bashPositional(top_positional, &.{});
        if (top_pos.len > 0) {
            if (tail.len > 0) tail = tail ++ " ";
            tail = tail ++ top_pos;
        }
        if (tail.len > 0) s = s ++ "    COMPREPLY=(" ++ tail ++ ")\n";
        s = s ++ "}\n";
        s = s ++ "complete -o filenames -F _" ++ cmd ++ " " ++ cmd ++ "\n";
        return s;
    }
}

// ── zsh ────────────────────────────────────────────────────────────────

/// One `_arguments` spec. zsh distinguishes an attached-only value (`--opt=-`)
/// from one that may be separated (`--opt`), and `::` from `:` makes the value
/// optional — exactly the `--diagnostics=fmt` vs `--timings[=fmt]` distinction
/// the hand-written script could not express (it declared both as separable,
/// so it completed `--diagnostics json`, which the parser rejects).
fn zshSpec(comptime f: ShellFlag, comptime long: bool) []const u8 {
    comptime {
        const name = if (long) f.long else (f.short orelse return "");
        if (f.value == .none) return "'" ++ name ++ "[" ++ f.desc ++ "]'";
        const action = switch (f.kind) {
            .none => ":" ++ f.value_name ++ ":",
            .file => ":" ++ f.value_name ++ ":_files",
            .dir => ":" ++ f.value_name ++ ":_files -/",
            .choice => ":" ++ f.value_name ++ ":(" ++ joinWords(f.choices) ++ ")",
        };
        return switch (f.value) {
            .none => "",
            .separate => "'" ++ name ++ "[" ++ f.desc ++ "]" ++ action ++ "'",
            .inline_eq => "'" ++ name ++ "=-[" ++ f.desc ++ "]" ++ action ++ "'",
            .inline_eq_optional => "'" ++ name ++ "=-[" ++ f.desc ++ "]:" ++ action ++ "'",
        };
    }
}

fn zshSpecLines(comptime flags: []const ShellFlag) []const []const u8 {
    comptime {
        var out: []const []const u8 = &.{};
        for (flags) |f| {
            out = out ++ [_][]const u8{zshSpec(f, true)};
            if (f.short != null) out = out ++ [_][]const u8{zshSpec(f, false)};
        }
        return out;
    }
}

fn zshPositionalLines(comptime pos: spec.Positional, comptime choices: []const []const u8) []const []const u8 {
    return switch (pos) {
        .none => &.{},
        .scm_file => &.{"'*:file:_files -g \"*.scm\"'"},
        .path => &.{"'*:path:_files'"},
        .opaque_word => &.{"'*:argument:'"},
        .choice => &.{"'1:action:(" ++ joinWords(choices) ++ ")'"},
    };
}

/// Emit `_arguments -s` with one spec per line, backslash-continued.
fn zshArguments(comptime indent: []const u8, comptime lines: []const []const u8) []const u8 {
    comptime {
        var s: []const u8 = indent ++ "_arguments -s";
        for (lines) |line| s = s ++ " \\\n" ++ indent ++ "    " ++ line;
        return s ++ "\n";
    }
}

fn zshScript(
    comptime cmd: []const u8,
    comptime top_flags: []const ShellFlag,
    comptime subs: []const SubcommandDesc,
    comptime top_positional: spec.Positional,
) []const u8 {
    comptime {
        @setEvalBranchQuota(2_000_000);
        var s: []const u8 = "#compdef " ++ cmd ++ "\n";
        s = s ++ "# generated from src/cli_spec.zig, do not edit\n\n";
        s = s ++ "_" ++ cmd ++ "() {\n";
        if (subs.len > 0) {
            s = s ++ "    local sub=\"\" word\n";
            s = s ++ "    for word in \"${words[@]:1:$(( CURRENT > 2 ? CURRENT-2 : 0 ))}\"; do\n";
            s = s ++ "        case \"$word\" in\n";
            s = s ++ "            " ++ subcommandNames(subs, "|") ++ ") sub=\"$word\"; break ;;\n";
            s = s ++ "        esac\n";
            s = s ++ "    done\n\n";
            s = s ++ "    case \"$sub\" in\n";
            for (subs) |sub| {
                const extra: []const ShellFlag = if (sub.global_flags_ok)
                    withoutOverlap(top_flags, sub.flags)
                else
                    &.{};
                const lines = zshSpecLines(sub.flags) ++ zshSpecLines(extra) ++
                    zshPositionalLines(sub.positional, sub.choices);
                s = s ++ "        " ++ sub.name ++ ")\n";
                s = s ++ zshArguments("            ", lines);
                s = s ++ "            return ;;\n";
            }
            s = s ++ "    esac\n\n";
        }
        var top: []const []const u8 = zshSpecLines(top_flags);
        if (subs.len > 0) {
            top = top ++ [_][]const u8{"'1:command or file:_alternative \"commands:command:(" ++
                subcommandNames(subs, " ") ++ ")\" \"files:file:_files\"'"};
        }
        top = top ++ zshPositionalLines(top_positional, &.{});
        s = s ++ zshArguments("    ", top);
        s = s ++ "}\n\n";
        s = s ++ "_" ++ cmd ++ " \"$@\"\n";
        return s;
    }
}

// ── fish ───────────────────────────────────────────────────────────────

fn fishFlagLine(comptime cmd: []const u8, comptime cond: []const u8, comptime f: ShellFlag) []const u8 {
    comptime {
        var s: []const u8 = "complete -c " ++ cmd;
        if (cond.len > 0) s = s ++ " -n '" ++ cond ++ "'";
        // A short-only flag (`-o`) lives in the `long` field, since that is
        // the whole of its spelling. fish wants `-s o`, not an empty `-l`.
        if (f.long.len > 2 and f.long[1] == '-') {
            s = s ++ " -l " ++ f.long[2..];
        } else {
            s = s ++ " -s " ++ f.long[1..];
        }
        if (f.short) |sh| s = s ++ " -s " ++ sh[1..];
        switch (f.value) {
            .none => {},
            // fish has no optional-value form. The bare spelling is the one
            // users type, and `--timings=json` still parses if they attach a
            // value, so requiring one here would be the worse trade.
            .inline_eq_optional => {},
            .separate, .inline_eq => {
                s = s ++ " -r" ++ switch (f.kind) {
                    .file, .dir => " -F",
                    .choice => " -x -a '" ++ joinWords(f.choices) ++ "'",
                    .none => " -x",
                };
            },
        }
        return s ++ " -d '" ++ f.desc ++ "'\n";
    }
}

fn fishScript(
    comptime cmd: []const u8,
    comptime top_flags: []const ShellFlag,
    comptime subs: []const SubcommandDesc,
    comptime no_files: bool,
) []const u8 {
    comptime {
        @setEvalBranchQuota(2_000_000);
        var s: []const u8 = "# fish completions for " ++ cmd ++ " - generated from src/cli_spec.zig, do not edit\n";
        if (no_files) s = s ++ "complete -c " ++ cmd ++ " -f\n";

        // The subcommands that intercept argv in their own module reject every
        // global flag with exit 2, so suppress the global specs once one is
        // seen. The inline ones share cli.parse's loop and keep them.
        var scoped: []const u8 = "";
        for (subs) |sub| {
            if (sub.global_flags_ok) continue;
            if (scoped.len > 0) scoped = scoped ++ " ";
            scoped = scoped ++ sub.name;
        }
        const global_cond: []const u8 = if (scoped.len > 0)
            "not __fish_seen_subcommand_from " ++ scoped
        else
            "";
        for (top_flags) |f| s = s ++ fishFlagLine(cmd, global_cond, f);

        for (subs) |sub| {
            s = s ++ "complete -c " ++ cmd ++ " -n '__fish_use_subcommand' -a " ++ sub.name ++
                " -d '" ++ sub.desc ++ "'\n";
        }
        for (subs) |sub| {
            const cond = "__fish_seen_subcommand_from " ++ sub.name;
            for (sub.flags) |f| {
                // An inline subcommand shares the global specs emitted above;
                // only its own additions need a scoped line.
                if (sub.global_flags_ok and hasFlag(top_flags, f)) continue;
                s = s ++ fishFlagLine(cmd, cond, f);
            }
            if (sub.positional == .choice) {
                s = s ++ "complete -c " ++ cmd ++ " -n '" ++ cond ++ "' -a '" ++
                    joinWords(sub.choices) ++ "' -d 'Action'\n";
            }
        }
        return s;
    }
}

// ── The six scripts ────────────────────────────────────────────────────

const kaappi_top = kaappiTopFlags();
const thottam_top = spec.erase(spec.ThottamId, &spec.thottam_flags);

const kaappi_bash = bashScript("kaappi", kaappi_top, &spec.subcommands, allKaappiFlags(), .scm_file);
const kaappi_zsh = zshScript("kaappi", kaappi_top, &spec.subcommands, .path);
const kaappi_fish = fishScript("kaappi", kaappi_top, &spec.subcommands, false);

const thottam_bash = bashScript("thottam", thottam_top, &spec.thottam_subcommands, thottam_top, .none);
const thottam_zsh = zshScript("thottam", thottam_top, &spec.thottam_subcommands, .opaque_word);
const thottam_fish = fishScript("thottam", thottam_top, &spec.thottam_subcommands, true);

pub fn kaappi(shell: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, shell, "bash")) return kaappi_bash;
    if (std.mem.eql(u8, shell, "zsh")) return kaappi_zsh;
    if (std.mem.eql(u8, shell, "fish")) return kaappi_fish;
    return null;
}

pub fn thottam(shell: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, shell, "bash")) return thottam_bash;
    if (std.mem.eql(u8, shell, "zsh")) return thottam_zsh;
    if (std.mem.eql(u8, shell, "fish")) return thottam_fish;
    return null;
}

// ── Tests ──────────────────────────────────────────────────────────────
//
// The drift gate has two halves. `cli_spec.zig`'s comptime block guarantees
// the *tables* match the *parsers* (an exhaustive switch per table, plus a
// once-and-only-once check per enum variant). These guarantee the *scripts*
// match the tables, in both directions, for every shell.

const testing = std.testing;

const all_scripts = [_][]const u8{ kaappi_bash, kaappi_zsh, kaappi_fish, thottam_bash, thottam_zsh, thottam_fish };
/// For the completeness assertions: the bash entry is trimmed of its trailing
/// `complete …` registration line (see `bashOfferBody`).
const kaappi_scripts = [_][]const u8{ bashOfferBody(kaappi_bash), kaappi_zsh, kaappi_fish };
const thottam_scripts = [_][]const u8{ bashOfferBody(thottam_bash), thottam_zsh, thottam_fish };

fn isFlagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '-' or c == '_';
}

fn findWord(script: []const u8, word: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, script, i, word)) |at| {
        i = at + 1;
        const before_ok = at == 0 or !isFlagChar(script[at - 1]);
        const end = at + word.len;
        const after_ok = end >= script.len or !isFlagChar(script[end]);
        if (before_ok and after_ok) return true;
    }
    return false;
}

/// The part of a bash script that offers words, i.e. everything above the
/// trailing `complete -o filenames -F _x x` registration. Without this the
/// short flag `-o` matches that line's own `-o` and the assertion is vacuous.
fn bashOfferBody(script: []const u8) []const u8 {
    const at = std.mem.lastIndexOf(u8, script, "\ncomplete ") orelse return script;
    return script[0 .. at + 1];
}

/// True when `flag` is offered by `script`, in whichever spelling that shell
/// uses: bash and zsh write `--lib-path` / `-o` literally, fish writes
/// `-l lib-path` / `-s o`.
fn offersFlag(script: []const u8, flag: []const u8) bool {
    if (findWord(script, flag)) return true;
    var buf: [64]u8 = undefined;
    if (flag.len > 2 and flag[1] == '-') {
        const alt = std.fmt.bufPrint(&buf, "-l {s}", .{flag[2..]}) catch return false;
        return findWord(script, alt);
    }
    if (flag.len == 2) {
        const alt = std.fmt.bufPrint(&buf, "-s {s}", .{flag[1..]}) catch return false;
        return findWord(script, alt);
    }
    return false;
}

test "every shell is supported for both binaries" {
    for (spec.shells) |sh| {
        try testing.expect(kaappi(sh) != null);
        try testing.expect(thottam(sh) != null);
    }
    try testing.expect(kaappi("csh") == null);
    try testing.expect(thottam("csh") == null);
}

test "every script is non-empty, ASCII, and newline-terminated" {
    for (all_scripts) |script| {
        try testing.expect(script.len > 100);
        try testing.expectEqual(@as(u8, '\n'), script[script.len - 1]);
        // A NUL or a stray non-ASCII byte makes a script unsourceable, and an
        // em dash in a generated comment is the easy way to get one.
        for (script) |c| try testing.expect(c == '\n' or (c >= 0x20 and c <= 0x7e));
    }
}

test "completeness: every kaappi global flag appears in every kaappi script" {
    // The bug this unit exists for: --no-ir-opt was in the parser and in none
    // of the three scripts.
    for (kaappi_scripts) |script| {
        inline for (spec.global_flags) |f| {
            try testing.expect(offersFlag(script, f.long));
            if (f.short) |s| try testing.expect(offersFlag(script, s));
        }
    }
}

test "completeness: every subcommand and its own flags appear in every kaappi script" {
    for (kaappi_scripts) |script| {
        inline for (spec.subcommands) |sub| {
            try testing.expect(findWord(script, sub.name));
            inline for (sub.flags) |f| {
                try testing.expect(offersFlag(script, f.long));
                if (f.short) |s| try testing.expect(offersFlag(script, s));
            }
            inline for (sub.choices) |c| try testing.expect(findWord(script, c));
        }
    }
}

test "completeness: kaappi test's selection flags are offered" {
    // These postdate the hand-written scripts: none of the three offered
    // -j/--jobs, --changed, --list-affected or --since, and only bash had
    // --seed.
    for (kaappi_scripts) |script| {
        for ([_][]const u8{ "--jobs", "-j", "--changed", "--list-affected", "--since", "--seed" }) |f| {
            try testing.expect(offersFlag(script, f));
        }
    }
}

test "completeness: every thottam flag and subcommand appears in every thottam script" {
    for (thottam_scripts) |script| {
        inline for (spec.thottam_flags) |f| {
            try testing.expect(offersFlag(script, f.long));
            if (f.short) |s| try testing.expect(offersFlag(script, s));
        }
        inline for (spec.thottam_subcommands) |sub| {
            try testing.expect(findWord(script, sub.name));
        }
    }
}

test "soundness: no script offers a --flag no table declares" {
    // The reverse direction, and the worse one for a user: completing a flag
    // that errors. Scan every `--word` token in every script and require it to
    // name a real flag.
    for (all_scripts) |script| {
        var i: usize = 0;
        while (i + 2 < script.len) : (i += 1) {
            if (script[i] != '-' or script[i + 1] != '-') continue;
            if (i > 0 and isFlagChar(script[i - 1])) continue;
            var j = i + 2;
            while (j < script.len and isFlagChar(script[j])) j += 1;
            const token = script[i..j];
            if (token.len == 2) continue; // a bare `--` separator
            if (!isDeclaredFlag(token)) {
                std.debug.print("undeclared flag in a generated script: {s}\n", .{token});
                return error.UndeclaredFlag;
            }
        }
    }
}

fn isDeclaredFlag(token: []const u8) bool {
    inline for (spec.global_flags) |f| {
        if (std.mem.eql(u8, token, f.long)) return true;
    }
    inline for (spec.thottam_flags) |f| {
        if (std.mem.eql(u8, token, f.long)) return true;
    }
    inline for (spec.subcommands) |sub| {
        inline for (sub.flags) |f| {
            if (std.mem.eql(u8, token, f.long)) return true;
        }
    }
    return false;
}

test "soundness: the five out-of-line subcommands never see the global flags" {
    // zsh and fish used to offer all 21 global flags inside explain, features,
    // test, doctor and cache, whose own parsers reject 15 of them with exit 2.
    // Each shell scopes differently, so assert each shell's own mechanism.
    try testing.expect(std.mem.indexOf(u8, kaappi_fish, "not __fish_seen_subcommand_from explain features test doctor cache") != null);
    inline for (spec.subcommands) |sub| {
        if (sub.global_flags_ok) continue;
        // bash and zsh dispatch on the detected subcommand word.
        try testing.expect(std.mem.indexOf(u8, kaappi_bash, "        " ++ sub.name ++ ")\n") != null);
        try testing.expect(std.mem.indexOf(u8, kaappi_zsh, "        " ++ sub.name ++ ")\n") != null);
    }
    // And the offered set inside one is exactly its own table: `features`
    // accepts --json and --help and nothing else.
    const arm_start = std.mem.indexOf(u8, kaappi_bash, "        features)\n").?;
    const arm = kaappi_bash[arm_start .. arm_start + std.mem.indexOf(u8, kaappi_bash[arm_start..], "return ;;").?];
    try testing.expect(std.mem.indexOf(u8, arm, "--json") != null);
    try testing.expect(std.mem.indexOf(u8, arm, "--sandbox") == null);
    try testing.expect(std.mem.indexOf(u8, arm, "--lib-path") == null);
}

test "bash: value-taking flags get their own case arm" {
    try testing.expect(std.mem.indexOf(u8, kaappi_bash, "compgen -d") != null);
    try testing.expect(std.mem.indexOf(u8, kaappi_bash, "compgen -f") != null);
    // --completions completes the shell names it actually supports.
    try testing.expect(std.mem.indexOf(u8, kaappi_bash, "bash zsh fish") != null);
}

test "zsh: attached-only values use the =- spelling" {
    // `--diagnostics json` is not accepted by the parser, so the spec must not
    // offer a separated value; `--timings` additionally makes it optional.
    try testing.expect(std.mem.indexOf(u8, kaappi_zsh, "'--diagnostics=-[") != null);
    try testing.expect(std.mem.indexOf(u8, kaappi_zsh, "'--timings=-[") != null);
    try testing.expect(std.mem.indexOf(u8, kaappi_zsh, "'--diagnostics[") == null);
}

test "fish: the bare --timings spelling stays completable" {
    // fish cannot express an optional value; requiring one would stop the bare
    // spelling — the common one — from ever completing.
    try testing.expect(std.mem.indexOf(u8, kaappi_fish, " -l timings -d ") != null);
}

test "every line has balanced quotes" {
    // A stray quote silently swallows the rest of the file when sourced.
    for (all_scripts) |script| {
        var it = std.mem.splitScalar(u8, script, '\n');
        while (it.next()) |line| {
            var singles: usize = 0;
            var doubles: usize = 0;
            for (line) |c| {
                if (c == '\'') singles += 1;
                if (c == '"') doubles += 1;
            }
            try testing.expectEqual(@as(usize, 0), singles % 2);
            try testing.expectEqual(@as(usize, 0), doubles % 2);
        }
    }
}
