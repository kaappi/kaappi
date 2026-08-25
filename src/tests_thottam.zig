//! Audit-campaign v2 Phase 6E: `thottam`, the package manager.
//!
//! The three pre-existing tests here covered the caret operator only. This
//! file covers the rest of the surface that needs no network: version
//! parsing, the seven constraint operators and their boundaries, the
//! `name[@ver][::url]` spec grammar, `kaappi.pkg` manifest parsing, the
//! package-name guard that keeps an install inside `$KAAPPI_HOME/lib`, and
//! the lockfile reader/writer round trip.
//!
//! **Oracle.** For the constraint operators the oracle is SemVer 2.0.0
//! (semver.org) for what a *version* is, and node-semver's range grammar
//! (github.com/npm/node-semver, "Ranges") for what `^` and `~` *mean* —
//! `^` and `~` are not in the SemVer spec at all, they are npm's, and every
//! ecosystem that spells them this way inherited them from npm. Where the
//! two could disagree the assertion says which one it is pinning.
//!
//! Assertions that document a *filed* defect are commented out with a
//! `FAIL: #N` marker directly above, per the campaign protocol: the fix PR
//! re-enables them. They state the property that *should* hold, never the
//! symptom that currently does.

const std = @import("std");
const platform = @import("platform.zig");
const thottam = @import("thottam.zig");
const semver = @import("thottam_semver.zig");
const state = @import("thottam_state.zig");
const tfs = @import("thottam_fs.zig");

const Semver = semver.Semver;

fn sv(major: u32, minor: u32, patch: u32) Semver {
    return .{ .major = major, .minor = minor, .patch = patch };
}

/// `<op><ver>` parsed through the same entry point `resolveVersion` uses,
/// then asked about `v`. Fails the test if the constraint does not parse —
/// a constraint that silently fails to parse is reported by thottam as
/// "no version matching", which is why every table below goes through here
/// rather than constructing a `Constraint` by hand.
fn allows(spec: []const u8, v: Semver) !bool {
    const c = semver.parseSingleConstraint(spec) orelse return error.ConstraintDidNotParse;
    return c.matches(v);
}

// ---------------------------------------------------------------------------
// Semver.parse — what counts as a version at all
// ---------------------------------------------------------------------------

test "Semver.parse accepts X.Y.Z with and without the conventional v prefix" {
    try std.testing.expectEqual(sv(1, 2, 3), Semver.parse("1.2.3").?);
    try std.testing.expectEqual(sv(1, 2, 3), Semver.parse("v1.2.3").?);
    try std.testing.expectEqual(sv(0, 0, 0), Semver.parse("0.0.0").?);
    try std.testing.expectEqual(sv(0, 0, 0), Semver.parse("v0.0.0").?);
}

test "Semver.parse defaults omitted trailing components to zero" {
    // Deliberate leniency: git tags in this ecosystem are sometimes `v1.2`.
    // The filled value is 0, but `written` records how much was written so
    // `^`/`~` can tell `~1` from `~1.0.0` (#2131).
    const one_two = Semver.parse("1.2").?;
    try std.testing.expectEqual(sv(1, 2, 0).major, one_two.major);
    try std.testing.expectEqual(sv(1, 2, 0).minor, one_two.minor);
    try std.testing.expectEqual(sv(1, 2, 0).patch, one_two.patch);
    try std.testing.expectEqual(@as(u8, 2), one_two.written);
    const one = Semver.parse("1").?;
    try std.testing.expectEqual(sv(1, 0, 0).major, one.major);
    try std.testing.expectEqual(@as(u8, 1), one.written);
    try std.testing.expectEqual(@as(u8, 2), Semver.parse("v1.2").?.written);
    try std.testing.expectEqual(@as(u8, 3), Semver.parse("1.2.3").?.written);
}

test "Semver.parse rejects non-numeric, signed and empty components" {
    try std.testing.expect(Semver.parse("") == null);
    try std.testing.expect(Semver.parse("v") == null);
    try std.testing.expect(Semver.parse("vv1.2.3") == null);
    try std.testing.expect(Semver.parse("a.b.c") == null);
    try std.testing.expect(Semver.parse("1.2.x") == null);
    try std.testing.expect(Semver.parse("1.two.3") == null);
    try std.testing.expect(Semver.parse("-1.2.3") == null);
    try std.testing.expect(Semver.parse("1.-2.3") == null);
    try std.testing.expect(Semver.parse("1..3") == null);
    try std.testing.expect(Semver.parse("3junk") == null);
    try std.testing.expect(Semver.parse("1.2.3junk") == null);
    try std.testing.expect(Semver.parse("0x10.0.0") == null);
}

test "Semver.parse rejects surrounding whitespace" {
    try std.testing.expect(Semver.parse(" 1.2.3") == null);
    try std.testing.expect(Semver.parse("1.2.3 ") == null);
    try std.testing.expect(Semver.parse("\t1.2.3") == null);
}

test "Semver.parse rejects SemVer pre-release and build metadata (2.0.0 s9, s10)" {
    // SemVer 2.0.0 s11: "a pre-release version has lower precedence than
    // the associated normal version". thottam has no precedence rule for
    // them, so excluding them from range matching (node-semver's default
    // for a range with no pre-release tag of its own) is the right answer.
    try std.testing.expect(Semver.parse("1.0.0-rc1") == null);
    try std.testing.expect(Semver.parse("1.0.0-alpha.1") == null);
    try std.testing.expect(Semver.parse("1.0.0+build.5") == null);
    try std.testing.expect(Semver.parse("1.0.0-rc1+build") == null);
}

test "Semver.parse does not overflow or wrap on out-of-range components" {
    try std.testing.expectEqual(sv(4294967295, 0, 0), Semver.parse("4294967295.0.0").?);
    try std.testing.expect(Semver.parse("4294967296.0.0") == null);
    try std.testing.expect(Semver.parse("99999999999999999999.0.0") == null);
    try std.testing.expect(Semver.parse("0.99999999999999999999.0") == null);
    try std.testing.expect(Semver.parse("0.0.99999999999999999999") == null);
}

test "Semver.parse rejects a tag that is not a version (issue #2130)" {
    // SemVer 2.0.0 s2: "A normal version number MUST take the form X.Y.Z
    // where X, Y, and Z are non-negative integers" — three components, not
    // "at least three". A `git ls-remote --tags` sweep sees whatever the
    // repo tagged, so a tag that is not a version must not become a
    // candidate release.
    try std.testing.expect(Semver.parse("2.0.0.nightly-UNRELEASED") == null);
    try std.testing.expect(Semver.parse("1.2.3.4") == null);
    try std.testing.expect(Semver.parse("1.2.3.") == null);

    // SemVer 2.0.0 s2: "and MUST NOT contain leading zeroes".
    try std.testing.expect(Semver.parse("01.02.03") == null);
    try std.testing.expect(Semver.parse("1.02.3") == null);
    try std.testing.expect(Semver.parse("1.2.03") == null);
    // A single 0 is not a leading zero.
    try std.testing.expect(Semver.parse("0.0.0") != null);

    // `std.fmt.parseInt` (the pre-fix parser) implements *Zig's*
    // integer-literal grammar — an explicit '+' sign and '_' digit
    // separators are both legal there and neither is a SemVer digit, so
    // `v1_0.0.0` parsed as version 10.0.0.
    try std.testing.expect(Semver.parse("+1.2.3") == null);
    try std.testing.expect(Semver.parse("1.+2.3") == null);
    try std.testing.expect(Semver.parse("1_0.0.0") == null);
    try std.testing.expect(Semver.parse("1.0.0_") == null);

    // Discriminating control — the adjacent malformed spellings ARE
    // rejected, so the leniency is specific to extra dot-separated
    // components, leading zeros, and Zig's own numeric-literal syntax.
    try std.testing.expect(Semver.parse("2.0.0-nightly") == null);
    try std.testing.expect(Semver.parse("2.0.0nightly") == null);
    try std.testing.expect(Semver.parse("2.0.0/4") == null);
    try std.testing.expect(Semver.parse("1-0.0.0") == null);
}

test "Semver.order is a total order over the three components" {
    try std.testing.expectEqual(std.math.Order.eq, Semver.order(sv(1, 2, 3), sv(1, 2, 3)));
    try std.testing.expectEqual(std.math.Order.lt, Semver.order(sv(1, 2, 3), sv(1, 2, 4)));
    try std.testing.expectEqual(std.math.Order.lt, Semver.order(sv(1, 2, 3), sv(1, 3, 0)));
    try std.testing.expectEqual(std.math.Order.lt, Semver.order(sv(1, 9, 9), sv(2, 0, 0)));
    try std.testing.expectEqual(std.math.Order.gt, Semver.order(sv(2, 0, 0), sv(1, 9, 9)));
    // Major dominates minor dominates patch, not a lexicographic string compare.
    try std.testing.expectEqual(std.math.Order.gt, Semver.order(sv(10, 0, 0), sv(9, 0, 0)));
    try std.testing.expectEqual(std.math.Order.gt, Semver.order(sv(1, 10, 0), sv(1, 9, 0)));
    try std.testing.expectEqual(std.math.Order.gt, Semver.order(sv(1, 0, 10), sv(1, 0, 9)));
}

// ---------------------------------------------------------------------------
// The seven constraint operators, at their boundaries
// ---------------------------------------------------------------------------

test "constraint >= includes its own version and everything above" {
    try std.testing.expect(try allows(">=1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows(">=1.2.3", sv(1, 2, 4)));
    try std.testing.expect(try allows(">=1.2.3", sv(99, 0, 0)));
    try std.testing.expect(!try allows(">=1.2.3", sv(1, 2, 2)));
    try std.testing.expect(!try allows(">=1.2.3", sv(0, 9, 9)));
}

test "constraint > excludes its own version" {
    try std.testing.expect(!try allows(">1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows(">1.2.3", sv(1, 2, 4)));
    try std.testing.expect(!try allows(">1.2.3", sv(1, 2, 2)));
}

test "constraint <= includes its own version and everything below" {
    try std.testing.expect(try allows("<=1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows("<=1.2.3", sv(1, 2, 2)));
    try std.testing.expect(try allows("<=1.2.3", sv(0, 0, 0)));
    try std.testing.expect(!try allows("<=1.2.3", sv(1, 2, 4)));
}

test "constraint < excludes its own version" {
    try std.testing.expect(!try allows("<1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows("<1.2.3", sv(1, 2, 2)));
    try std.testing.expect(!try allows("<1.2.3", sv(1, 3, 0)));
}

test "a bare version inside a comma list is an equality constraint" {
    // Reachable only from a comma list: isConstraintSpec routes a bare
    // `pkg@1.2.3` to `git checkout` as a literal ref, never to the matcher.
    try std.testing.expect(try allows("1.2.3", sv(1, 2, 3)));
    try std.testing.expect(!try allows("1.2.3", sv(1, 2, 4)));
    try std.testing.expect(!try allows("1.2.3", sv(1, 2, 2)));
}

test "caret ^X.Y.Z with X>0 is >=X.Y.Z <(X+1).0.0 (node-semver Ranges)" {
    try std.testing.expect(try allows("^1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows("^1.2.3", sv(1, 2, 4)));
    try std.testing.expect(try allows("^1.2.3", sv(1, 99, 99)));
    try std.testing.expect(!try allows("^1.2.3", sv(1, 2, 2)));
    try std.testing.expect(!try allows("^1.2.3", sv(1, 1, 99)));
    try std.testing.expect(!try allows("^1.2.3", sv(2, 0, 0)));
    try std.testing.expect(!try allows("^1.2.3", sv(0, 99, 99)));
}

test "caret ^0.Y.Z with Y>0 is >=0.Y.Z <0.(Y+1).0 (node-semver Ranges)" {
    try std.testing.expect(try allows("^0.2.3", sv(0, 2, 3)));
    try std.testing.expect(try allows("^0.2.3", sv(0, 2, 99)));
    try std.testing.expect(!try allows("^0.2.3", sv(0, 2, 2)));
    try std.testing.expect(!try allows("^0.2.3", sv(0, 3, 0)));
    try std.testing.expect(!try allows("^0.2.3", sv(1, 0, 0)));
}

test "caret ^0.0.Z is exactly Z — >=0.0.Z <0.0.(Z+1) (node-semver Ranges)" {
    try std.testing.expect(try allows("^0.0.3", sv(0, 0, 3)));
    try std.testing.expect(!try allows("^0.0.3", sv(0, 0, 4)));
    try std.testing.expect(!try allows("^0.0.3", sv(0, 0, 2)));
    try std.testing.expect(!try allows("^0.0.3", sv(0, 1, 0)));
}

test "caret on an abbreviated range (issue #2131)" {
    // node-semver: `^1` is `>=1.0.0 <2.0.0`. This one is right, because
    // filling the omitted components with 0 happens to give the same answer.
    try std.testing.expect(try allows("^1", sv(1, 0, 0)));
    try std.testing.expect(try allows("^1", sv(1, 9, 9)));
    try std.testing.expect(!try allows("^1", sv(2, 0, 0)));

    // node-semver: `^0.2` is `>=0.2.0 <0.3.0`. Also right.
    try std.testing.expect(try allows("^0.2", sv(0, 2, 9)));
    try std.testing.expect(!try allows("^0.2", sv(0, 3, 0)));

    // node-semver: `^0.0` is `>=0.0.0 <0.1.0` — the whole 0.0.x line.
    try std.testing.expect(try allows("^0.0", sv(0, 0, 5)));
    try std.testing.expect(try allows("^0.0", sv(0, 0, 0)));
    try std.testing.expect(!try allows("^0.0", sv(0, 1, 0)));
    try std.testing.expect(!try allows("^0.0", sv(1, 0, 0)));
}

test "tilde ~X.Y.Z is >=X.Y.Z <X.(Y+1).0 (node-semver Ranges)" {
    try std.testing.expect(try allows("~1.2.3", sv(1, 2, 3)));
    try std.testing.expect(try allows("~1.2.3", sv(1, 2, 99)));
    try std.testing.expect(!try allows("~1.2.3", sv(1, 2, 2)));
    try std.testing.expect(!try allows("~1.2.3", sv(1, 3, 0)));
    try std.testing.expect(!try allows("~1.2.3", sv(2, 2, 3)));
    try std.testing.expect(!try allows("~1.2.3", sv(0, 2, 3)));
}

test "tilde on an abbreviated range (issue #2131)" {
    // node-semver: `~1.2` is `>=1.2.0 <1.3.0`. Right.
    try std.testing.expect(try allows("~1.2", sv(1, 2, 0)));
    try std.testing.expect(try allows("~1.2", sv(1, 2, 9)));
    try std.testing.expect(!try allows("~1.2", sv(1, 3, 0)));

    // node-semver: `~1` is `>=1.0.0 <2.0.0` — "allows minor-level changes
    // when only the major version is specified".
    try std.testing.expect(try allows("~1", sv(1, 9, 0)));
    try std.testing.expect(try allows("~1", sv(1, 0, 0)));
    try std.testing.expect(!try allows("~1", sv(2, 0, 0)));

    // Discriminating control: `~1.0.0` and `~1` are DIFFERENT ranges — and
    // now behave differently here too: the fully-spelled form pins minor 0.
    try std.testing.expect(try allows("~1.0.0", sv(1, 0, 9)));
    try std.testing.expect(!try allows("~1.0.0", sv(1, 1, 0)));
}

// ---------------------------------------------------------------------------
// parseConstraints — the comma-separated range
// ---------------------------------------------------------------------------

fn rangeAllows(spec: []const u8, v: Semver) !bool {
    const cs = semver.parseConstraints(spec) orelse return error.RangeDidNotParse;
    return semver.matchesAllConstraints(v, cs);
}

test "parseConstraints conjoins every comma-separated part" {
    try std.testing.expect(try rangeAllows(">=1.0.0,<2.0.0", sv(1, 9, 9)));
    try std.testing.expect(!try rangeAllows(">=1.0.0,<2.0.0", sv(2, 0, 0)));
    try std.testing.expect(!try rangeAllows(">=1.0.0,<2.0.0", sv(0, 9, 9)));
    // An unsatisfiable range parses and simply matches nothing.
    try std.testing.expect(!try rangeAllows(">=2.0.0,<1.0.0", sv(1, 5, 0)));
    try std.testing.expect(!try rangeAllows(">=2.0.0,<1.0.0", sv(2, 5, 0)));
}

test "parseConstraints tolerates surrounding quotes and spaces after commas" {
    // `depends: kaappi-net@">=0.2.0"` keeps its quotes through the manifest.
    try std.testing.expect(try rangeAllows("\">=1.0.0\"", sv(1, 0, 0)));
    try std.testing.expect(try rangeAllows("\">=1.0.0,<2.0.0\"", sv(1, 5, 0)));
    try std.testing.expect(try rangeAllows(">=1.0.0, <2.0.0", sv(1, 5, 0)));
}

test "parseConstraints rejects malformed ranges rather than matching loosely" {
    try std.testing.expect(semver.parseConstraints("") == null);
    try std.testing.expect(semver.parseConstraints(">=") == null);
    try std.testing.expect(semver.parseConstraints("^") == null);
    try std.testing.expect(semver.parseConstraints("~") == null);
    try std.testing.expect(semver.parseConstraints(">") == null);
    try std.testing.expect(semver.parseConstraints("<") == null);
    try std.testing.expect(semver.parseConstraints(">=>1.0.0") == null);
    try std.testing.expect(semver.parseConstraints(">>1.0.0") == null);
    try std.testing.expect(semver.parseConstraints("^~1.0.0") == null);
    try std.testing.expect(semver.parseConstraints(">=1.0.0,") == null);
    try std.testing.expect(semver.parseConstraints(",>=1.0.0") == null);
    try std.testing.expect(semver.parseConstraints(">=1.0.0,,<2.0.0") == null);
    try std.testing.expect(semver.parseConstraints(">=1.0.0-rc1") == null);
    try std.testing.expect(semver.parseConstraints("\"\"") == null);
}

test "parseConstraints accepts a four-part range (issue #2132)" {
    try std.testing.expect(semver.parseConstraints(">=1.0.0,<2.0.0,>0.5.0,<=1.9.0") != null);
    // Four is the ceiling (`[4]?Constraint`): a fifth part is reported as a
    // too_many_parts diagnostic rather than silently nulling the range.
    var diag: semver.ConstraintParseError = undefined;
    try std.testing.expect(semver.parseConstraintsDiag(">=1.0.0,<2.0.0,>0.5.0,<=1.9.0,>0.1.0", &diag) == null);
    try std.testing.expectEqual(semver.ConstraintParseError{ .kind = .too_many_parts, .part_index = 4 }, diag);
    _ = semver.parseConstraintsDiag(">=1.0.0,<2.0.0", &diag); // parses; leaves no error

    // node-semver allows whitespace between an operator and its version
    // (`>= 1.0.0` is the same range as `>=1.0.0`).
    try std.testing.expect(semver.parseConstraints(">= 1.0.0") != null);
    try std.testing.expect(semver.parseConstraints(">=1.0.0, < 2.0.0") != null);
    try std.testing.expect(try allows(">= 1.0.0", sv(1, 0, 0)));
    try std.testing.expect(!try allows(">= 1.0.0", sv(0, 9, 9)));
}

test "parseConstraintsDiag names the offending part (issue #2132)" {
    var diag: semver.ConstraintParseError = undefined;
    // The second part is the malformed one; the first part parses fine.
    try std.testing.expect(semver.parseConstraintsDiag(">=1.0.0,>=>2.0.0", &diag) == null);
    try std.testing.expectEqual(semver.ConstraintParseError{ .kind = .bad_part, .part_index = 1 }, diag);

    // A pre-release in any part fails that part.
    try std.testing.expect(semver.parseConstraintsDiag(">=1.0.0-rc1", &diag) == null);
    try std.testing.expectEqual(@as(usize, 0), diag.part_index);

    // An empty spec has no part to name beyond the first.
    try std.testing.expect(semver.parseConstraintsDiag("", &diag) == null);
    try std.testing.expectEqual(@as(usize, 0), diag.part_index);
}

test "isConstraintSpec routes the six operator-led forms and nothing else" {
    try std.testing.expect(semver.isConstraintSpec(">=1.0.0"));
    try std.testing.expect(semver.isConstraintSpec(">1.0.0"));
    try std.testing.expect(semver.isConstraintSpec("<=1.0.0"));
    try std.testing.expect(semver.isConstraintSpec("<1.0.0"));
    try std.testing.expect(semver.isConstraintSpec("^1.0.0"));
    try std.testing.expect(semver.isConstraintSpec("~1.0.0"));
    try std.testing.expect(semver.isConstraintSpec("\">=1.0.0\""));
    // Everything else is a literal git ref for `git checkout`.
    try std.testing.expect(!semver.isConstraintSpec("1.0.0"));
    try std.testing.expect(!semver.isConstraintSpec("v1.0.0"));
    try std.testing.expect(!semver.isConstraintSpec("=1.0.0"));
    try std.testing.expect(!semver.isConstraintSpec("main"));
    try std.testing.expect(!semver.isConstraintSpec("abc123"));
    // Regression for #613: empty after quote trimming must not index [0].
    try std.testing.expect(!semver.isConstraintSpec(""));
    try std.testing.expect(!semver.isConstraintSpec("\"\""));
    try std.testing.expect(!semver.isConstraintSpec("\"\"\"\""));
}

// ---------------------------------------------------------------------------
// parsePkgSpec — name[@ver][::url]
// ---------------------------------------------------------------------------

test "parsePkgSpec splits at the first :: and the first @ before it" {
    const a = state.parsePkgSpec("pkg@v1.0.0::https://example.com/a/b");
    try std.testing.expectEqualStrings("pkg", a.name);
    try std.testing.expectEqualStrings("v1.0.0", a.ver.?);
    try std.testing.expectEqualStrings("https://example.com/a/b", a.source.?);
}

test "parsePkgSpec leaves @ and :: inside the URL alone" {
    // A userinfo@host URL must not be re-split: the @ search is confined to
    // the part before ::.
    const a = state.parsePkgSpec("pkg::https://user@host.example/repo.git");
    try std.testing.expectEqualStrings("pkg", a.name);
    try std.testing.expect(a.ver == null);
    try std.testing.expectEqualStrings("https://user@host.example/repo.git", a.source.?);

    // Only the FIRST :: separates; later ones belong to the URL.
    const b = state.parsePkgSpec("pkg::https://h/a::b");
    try std.testing.expectEqualStrings("pkg", b.name);
    try std.testing.expectEqualStrings("https://h/a::b", b.source.?);

    const c = state.parsePkgSpec("pkg@v1::https://u@h/r::x");
    try std.testing.expectEqualStrings("pkg", c.name);
    try std.testing.expectEqualStrings("v1", c.ver.?);
    try std.testing.expectEqualStrings("https://u@h/r::x", c.source.?);
}

test "parsePkgSpec drops an option-shaped source URL (issue #614 guard)" {
    // A URL starting with '-' would be parsed as an option by git even
    // behind `--`; it is discarded so the org default is used instead.
    try std.testing.expect(state.parsePkgSpec("pkg::-upload-pack=evil").source == null);
    try std.testing.expect(state.parsePkgSpec("pkg::--upload-pack=evil").source == null);
    // An empty URL likewise falls back to the org default.
    try std.testing.expect(state.parsePkgSpec("pkg::").source == null);
    // Discriminating control: an ordinary URL survives.
    try std.testing.expect(state.parsePkgSpec("pkg::https://h/r").source != null);
}

test "parsePkgSpec on degenerate specs (issue #2132)" {
    // An empty name is produced, not rejected here — isValidPkgName is the
    // gate, and it runs on every path that builds a filesystem path.
    try std.testing.expectEqualStrings("", state.parsePkgSpec("::https://h/r").name);
    try std.testing.expectEqualStrings("", state.parsePkgSpec("@v1").name);
    try std.testing.expectEqualStrings("", state.parsePkgSpec("").name);

    // A trailing @ with nothing after it should mean "no version pinned",
    // the same as omitting the @ entirely.
    try std.testing.expect(state.parsePkgSpec("pkg@").ver == null);

    // Discriminating control: omitting the @ does give null.
    try std.testing.expect(state.parsePkgSpec("pkg").ver == null);
}

// ---------------------------------------------------------------------------
// isValidPkgName — the guard that keeps an install inside $KAAPPI_HOME/lib
// ---------------------------------------------------------------------------

test "isValidPkgName rejects every byte that could leave the install tree" {
    // Exhaustive over the byte range: a package name reaches
    // joinPath(src_dir, name) and joinPath(lib_dir, name), so the accepted
    // set must contain no separator, no '.', and nothing a shell or a
    // Windows path parser treats specially. Property, not a spot check —
    // a future "allow dots in names" change has to come here first.
    var b: u16 = 0;
    while (b <= 255) : (b += 1) {
        const c: u8 = @intCast(b);
        const one = [_]u8{c};
        const want = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        try std.testing.expectEqual(want, state.isValidPkgName(&one));
    }
}

test "isValidPkgName rejects traversal, absolute and empty names" {
    try std.testing.expect(!state.isValidPkgName(""));
    try std.testing.expect(!state.isValidPkgName("."));
    try std.testing.expect(!state.isValidPkgName(".."));
    try std.testing.expect(!state.isValidPkgName("../evil"));
    try std.testing.expect(!state.isValidPkgName("../../etc/passwd"));
    try std.testing.expect(!state.isValidPkgName("a/../../b"));
    try std.testing.expect(!state.isValidPkgName("/tmp/evil"));
    try std.testing.expect(!state.isValidPkgName("C:\\evil"));
    try std.testing.expect(!state.isValidPkgName("a\\b"));
    try std.testing.expect(!state.isValidPkgName("foo.bar"));
    try std.testing.expect(!state.isValidPkgName("foo bar"));
    try std.testing.expect(!state.isValidPkgName("foo\x00bar"));
    try std.testing.expect(!state.isValidPkgName("foo\nbar"));
    try std.testing.expect(!state.isValidPkgName("~root"));
    try std.testing.expect(!state.isValidPkgName("$HOME"));
    try std.testing.expect(!state.isValidPkgName("kaappi—json")); // U+2014, not '-'
}

test "isValidPkgName accepts the shapes the ecosystem actually uses" {
    try std.testing.expect(state.isValidPkgName("kaappi-json"));
    try std.testing.expect(state.isValidPkgName("kaappi_json"));
    try std.testing.expect(state.isValidPkgName("kaappi-160"));
    try std.testing.expect(state.isValidPkgName("a"));
    try std.testing.expect(state.isValidPkgName("A"));
    try std.testing.expect(state.isValidPkgName("0"));
}

// ---------------------------------------------------------------------------
// kaappi.pkg manifest parsing
// ---------------------------------------------------------------------------

test "parsePkgManifest reads the two read fields and ignores the rest" {
    // Only depends and build are read. name, source and version are
    // documented as ignored — a manifest that lies about its identity or
    // hosting must not change the install (issue #2138).
    const m = state.parsePkgManifest(
        \\name: kaappi-web
        \\source: https://evil.example.com/not-this-repo
        \\version: 99.99.99
        \\depends: kaappi-http kaappi-json
        \\build: make
        \\
    );
    try std.testing.expectEqualStrings("kaappi-http kaappi-json", m.depends.?);
    try std.testing.expectEqualStrings("make", m.build_cmd.?);
}

test "parsePkgManifest tolerates CRLF line endings" {
    // thottam runs on Windows under Git Bash; a manifest checked out with
    // core.autocrlf=true has \r before every \n.
    const m = state.parsePkgManifest("name: kaappi-web\r\ndepends: kaappi-http\r\nbuild: make\r\n");
    try std.testing.expectEqualStrings("kaappi-http", m.depends.?);
    try std.testing.expectEqualStrings("make", m.build_cmd.?);
}

test "parsePkgManifest ignores unknown keys and near-miss key names" {
    const m = state.parsePkgManifest(
        \\# a comment line
        \\names: not-the-name
        \\builds: not-the-build
        \\sources: not-the-source
        \\dependency: not-the-depends
        \\version: 1.0.0
        \\name: real
        \\source: https://h/real
        \\depends: real-dep
        \\
    );
    try std.testing.expectEqualStrings("real-dep", m.depends.?);
    try std.testing.expect(m.build_cmd == null);
}

test "parsePkgManifest takes the last of duplicate keys" {
    const m = state.parsePkgManifest("depends: a\ndepends: b\nbuild: a\nbuild: b\n");
    try std.testing.expectEqualStrings("b", m.depends.?);
    try std.testing.expectEqualStrings("b", m.build_cmd.?);
}

test "parsePkgManifest requires the key at column 0" {
    // Strictness worth pinning: an indented key is silently dropped, so a
    // future whitespace-tolerant rewrite has to notice this test.
    const m = state.parsePkgManifest("  depends: indented\n\tbuild: tabbed\n");
    try std.testing.expect(m.depends == null);
    try std.testing.expect(m.build_cmd == null);
}

test "parsePkgManifest on missing and empty values" {
    const none = state.parsePkgManifest("");
    try std.testing.expect(none.depends == null);
    try std.testing.expect(none.build_cmd == null);

    // An empty `build:` should mean "no build command", not "run the empty
    // command" — thottam used to print "Building <pkg>..." and run
    // `/bin/sh -c ""`.
    try std.testing.expect(state.parsePkgManifest("build:\n").build_cmd == null);
    try std.testing.expect(state.parsePkgManifest("build: \n").build_cmd == null);
    // A later non-empty build: still wins after an empty one.
    try std.testing.expectEqualStrings("make", state.parsePkgManifest("build:\nbuild: make\n").build_cmd.?);

    // Discriminating control: a genuinely absent build: key is null.
    try std.testing.expect(state.parsePkgManifest("depends: x\n").build_cmd == null);
}

test "parseField trims the value but not the key" {
    try std.testing.expectEqualStrings("value", state.parseField("key: value", "key:").?);
    try std.testing.expectEqualStrings("value", state.parseField("key:value", "key:").?);
    try std.testing.expectEqualStrings("value", state.parseField("key:  value  ", "key:").?);
    try std.testing.expectEqualStrings("value", state.parseField("key:\tvalue\r", "key:").?);
    try std.testing.expectEqualStrings("a  b", state.parseField("key: a  b ", "key:").?);
    try std.testing.expect(state.parseField("other: value", "key:") == null);
    try std.testing.expect(state.parseField(" key: value", "key:") == null);
    try std.testing.expect(state.parseField("", "key:") == null);
}

// ---------------------------------------------------------------------------
// Lockfile and installed-list round trips
// ---------------------------------------------------------------------------

fn tempPath(buf: []u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/kaappi-thottam-6e-{d}-{s}", .{ platform.tempDir(), platform.getPid(), name });
}

test "updateLockfile round-trips through getLockedEntry" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock1");
    defer thottam.removeDir(allocator, lock) catch {};

    try state.updateLockfile(allocator, lock, "kaappi-json", "abc123", null);
    const e = state.getLockedEntry(allocator, lock, "kaappi-json").?;
    defer allocator.free(e.sha);
    defer if (e.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("abc123", e.sha);
    try std.testing.expect(e.source == null);
}

test "updateLockfile records and replaces the provenance URL in place" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock2");
    defer thottam.removeDir(allocator, lock) catch {};

    try state.updateLockfile(allocator, lock, "a", "sha-a", "https://h/a");
    try state.updateLockfile(allocator, lock, "b", "sha-b", null);
    try state.updateLockfile(allocator, lock, "a", "sha-a2", "https://h/a2");

    const ea = state.getLockedEntry(allocator, lock, "a").?;
    defer allocator.free(ea.sha);
    defer if (ea.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-a2", ea.sha);
    try std.testing.expectEqualStrings("https://h/a2", ea.source.?);

    // Rewriting one entry must not disturb its neighbour.
    const eb = state.getLockedEntry(allocator, lock, "b").?;
    defer allocator.free(eb.sha);
    defer if (eb.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-b", eb.sha);

    // And must not duplicate the rewritten one, nor leave the superseded
    // line behind. The old line is `a sha-a https://h/a` — matching on
    // `sha-a` alone would also match `sha-a2`, so the whole line is the
    // only spelling that can actually fail here.
    const content = try thottam.readFile(allocator, lock);
    defer allocator.free(content);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, content, "a sha-a2 https://h/a2\n"));
    try std.testing.expect(std.mem.indexOf(u8, content, "a sha-a https://h/a\n") == null);
    // Two entries in, two lines out — an in-place rewrite, not an append.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, content, "\n"));
}

test "lockfile lookup does not match a package whose name is a prefix (issue #403)" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock3");
    defer thottam.removeDir(allocator, lock) catch {};

    try state.updateLockfile(allocator, lock, "kaappi-net-extra", "sha-extra", null);
    // "kaappi-net" is a strict prefix of "kaappi-net-extra": the delimiter
    // check is what keeps this from returning the wrong entry.
    try std.testing.expect(state.getLockedEntry(allocator, lock, "kaappi-net") == null);

    try state.updateLockfile(allocator, lock, "kaappi-net", "sha-net", null);
    const e = state.getLockedEntry(allocator, lock, "kaappi-net").?;
    defer allocator.free(e.sha);
    defer if (e.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-net", e.sha);

    const e2 = state.getLockedEntry(allocator, lock, "kaappi-net-extra").?;
    defer allocator.free(e2.sha);
    defer if (e2.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-extra", e2.sha);
}

test "removeFromLockfile removes only the named entry" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock4");
    defer thottam.removeDir(allocator, lock) catch {};

    try state.updateLockfile(allocator, lock, "kaappi-net", "sha-net", null);
    try state.updateLockfile(allocator, lock, "kaappi-net-extra", "sha-extra", "https://h/x");
    try state.removeFromLockfile(allocator, lock, "kaappi-net");

    try std.testing.expect(state.getLockedEntry(allocator, lock, "kaappi-net") == null);
    const e = state.getLockedEntry(allocator, lock, "kaappi-net-extra").?;
    defer allocator.free(e.sha);
    defer if (e.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-extra", e.sha);
    try std.testing.expectEqualStrings("https://h/x", e.source.?);

    // Removing an absent package is a no-op, not an error.
    try state.removeFromLockfile(allocator, lock, "not-there");
    const still = state.getLockedEntry(allocator, lock, "kaappi-net-extra").?;
    defer allocator.free(still.sha);
    defer if (still.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("sha-extra", still.sha);
}

test "lockfile reader on a truncated or malformed file" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock5");
    defer thottam.removeDir(allocator, lock) catch {};

    // A name with no SHA and no delimiter: no entry, no crash.
    try thottam.writeFile(allocator, lock, "kaappi-json");
    try std.testing.expect(state.getLockedEntry(allocator, lock, "kaappi-json") == null);

    // Binary garbage: no entry, no crash.
    try thottam.writeFile(allocator, lock, "\x00\x01\xff\xfe\n\x7f");
    try std.testing.expect(state.getLockedEntry(allocator, lock, "kaappi-json") == null);

    // A name followed by a bare space: an empty SHA, reported as such.
    try thottam.writeFile(allocator, lock, "kaappi-json \n");
    const e = state.getLockedEntry(allocator, lock, "kaappi-json").?;
    defer allocator.free(e.sha);
    defer if (e.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings("", e.sha);

    // A missing file is null, not an error.
    var buf2: [512]u8 = undefined;
    const gone = try tempPath(&buf2, "lock5-absent");
    try std.testing.expect(state.getLockedEntry(allocator, gone, "kaappi-json") == null);
}

test "lockfile reader tolerates CRLF line endings (issue #2133)" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const lock = try tempPath(&buf, "lock6");
    defer thottam.removeDir(allocator, lock) catch {};

    const sha = "75f253e118c0976ac2caabec574af39394e7bc4e";
    try thottam.writeFile(allocator, lock, "kaappi-alpha " ++ "75f253e118c0976ac2caabec574af39394e7bc4e" ++ "\r\n");
    const e = state.getLockedEntry(allocator, lock, "kaappi-alpha").?;
    defer allocator.free(e.sha);
    defer if (e.source) |s| allocator.free(s);

    // The lockfile is meant to be committed and shared between machines, so
    // a checkout that normalised it to CRLF must still compare equal (#2133).
    try std.testing.expectEqualStrings(sha, e.sha);

    // Discriminating control: with LF, the same line reads back exactly.
    try thottam.writeFile(allocator, lock, "kaappi-alpha " ++ "75f253e118c0976ac2caabec574af39394e7bc4e" ++ "\n");
    const e2 = state.getLockedEntry(allocator, lock, "kaappi-alpha").?;
    defer allocator.free(e2.sha);
    defer if (e2.source) |s| allocator.free(s);
    try std.testing.expectEqualStrings(sha, e2.sha);
}

test "installed-list membership is exact, never a prefix match" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const inst = try tempPath(&buf, "inst1");
    defer thottam.removeDir(allocator, inst) catch {};

    try thottam.writeFile(allocator, inst, "kaappi-net-extra\nkaappi-json\n");
    try std.testing.expect(state.isInstalled(allocator, inst, "kaappi-json"));
    try std.testing.expect(state.isInstalled(allocator, inst, "kaappi-net-extra"));
    try std.testing.expect(!state.isInstalled(allocator, inst, "kaappi-net"));
    try std.testing.expect(!state.isInstalled(allocator, inst, "kaappi"));
    try std.testing.expect(!state.isInstalled(allocator, inst, "json"));

    try state.removeFromInstalled(allocator, inst, "kaappi-json");
    try std.testing.expect(!state.isInstalled(allocator, inst, "kaappi-json"));
    try std.testing.expect(state.isInstalled(allocator, inst, "kaappi-net-extra"));
}

test "installed-list membership tolerates CRLF line endings (issue #2133)" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    const inst = try tempPath(&buf, "inst2");
    defer thottam.removeDir(allocator, inst) catch {};

    try thottam.writeFile(allocator, inst, "kaappi-json\r\nkaappi-csv\n");
    try std.testing.expect(state.isInstalled(allocator, inst, "kaappi-json"));
    try std.testing.expect(state.isInstalled(allocator, inst, "kaappi-csv"));
    try std.testing.expect(!state.isInstalled(allocator, inst, "kaappi"));
}

test "appendLockEntry emits the documented two- and three-column shapes" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try state.appendLockEntry(&out, allocator, "a", "sha-a", null);
    try state.appendLockEntry(&out, allocator, "b", "sha-b", "https://h/b");
    try std.testing.expectEqualStrings("a sha-a\nb sha-b https://h/b\n", out.items);
}

// ---------------------------------------------------------------------------
// Issue #2144 — list/verify/update must not build paths from names read back
// out of installed.txt / thottam.lock
// ---------------------------------------------------------------------------
//
// isValidPkgName guards install and remove; the fix (landed with #2289) added
// the same guard to every read path that hands a state-file name to
// joinPath. These tests drive the three commands against a throwaway
// $KAAPPI_HOME whose state files contain a traversal-shaped name, and assert
// on what the commands print and return. The commands write their reports
// straight to fd 1/fd 2, so the descriptor swap below is the observation
// point; before the guard, each of these printed the hostile name (having
// joined it onto src_dir/lib_dir) or exited clean.

const Captured = struct {
    out: []const u8,
    err: ?anyerror,
};

/// Run `func(args)` with fd 1 (and fd 2 when `stderr_too`) pointed at a pipe,
/// and return everything it wrote plus the error it returned, if any. Both
/// descriptors are restored before the pipe is drained, so read() sees EOF
/// instead of blocking on a descriptor that still aliases the write end.
/// pipe/dup/dup2 are CRT calls on Windows too, so the swap is portable.
fn captureOutput(comptime stderr_too: bool, comptime func: anytype, args: anytype) !Captured {
    const allocator = std.testing.allocator;

    var fds: [2]platform.fd_t = undefined;
    if (platform.pipe(&fds) != 0) return error.PipeFailed;

    const saved_out = platform.dup(1);
    if (saved_out < 0) {
        platform.close(fds[0]);
        platform.close(fds[1]);
        return error.DupFailed;
    }
    const saved_err: platform.fd_t = if (stderr_too) platform.dup(2) else -1;
    if (stderr_too and saved_err < 0) {
        platform.close(fds[0]);
        platform.close(fds[1]);
        platform.close(saved_out);
        return error.DupFailed;
    }

    var cap: Captured = .{ .out = "", .err = null };

    _ = platform.dup2(fds[1], 1);
    if (stderr_too) _ = platform.dup2(fds[1], 2);
    platform.close(fds[1]);

    if (@call(.auto, func, args)) |_| {} else |err| {
        cap.err = err;
    }

    _ = platform.dup2(saved_out, 1);
    if (stderr_too) _ = platform.dup2(saved_err, 2);
    platform.close(saved_out);
    if (stderr_too) platform.close(saved_err);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    var chunk: [1024]u8 = undefined;
    while (true) {
        const n = platform.read(fds[0], &chunk, chunk.len);
        if (n <= 0) break;
        try buf.appendSlice(allocator, chunk[0..@intCast(n)]);
    }
    platform.close(fds[0]);
    cap.out = try buf.toOwnedSlice(allocator);
    return cap;
}

/// A throwaway `$KAAPPI_HOME` plus the Config thottam's main() derives from
/// it. `outside` is a directory next to `home`: the hostile names in these
/// tests are `../..` traversals out of `<home>/src` and resolve onto it. It
/// is created up front (with `src` and `lib` inside home, as main()'s
/// ensureDirs would have) so a regression that does follow a hostile name
/// finds a plain non-repo directory and returns quietly rather than a lucky
/// ENOENT — the assertions are on what the commands print, and a
/// process-killing failure path would wreck the rest of the test run.
const TmpHome = struct {
    home: []u8,
    outside: []u8,
    config: thottam.Config,

    fn init(allocator: std.mem.Allocator, tag: []const u8) !TmpHome {
        const home = try std.fmt.allocPrint(allocator, "{s}/kaappi-thottam-2144-home-{d}-{s}", .{ platform.tempDir(), platform.getPid(), tag });
        errdefer allocator.free(home);
        try tfs.makeDirRecursive(allocator, home);

        const outside = try std.fmt.allocPrint(allocator, "{s}/kaappi-thottam-2144-outside-{d}-{s}", .{ platform.tempDir(), platform.getPid(), tag });
        errdefer allocator.free(outside);
        try tfs.makeDirRecursive(allocator, outside);

        const lib_dir = try std.mem.concat(allocator, u8, &.{ home, "/lib" });
        errdefer allocator.free(lib_dir);
        const src_dir = try std.mem.concat(allocator, u8, &.{ home, "/src" });
        errdefer allocator.free(src_dir);
        // The kernel resolves ".." against the real tree, so a traversal out
        // of src only names `outside` if src itself exists.
        try tfs.makeDirRecursive(allocator, src_dir);
        try tfs.makeDirRecursive(allocator, lib_dir);
        const installed = try std.mem.concat(allocator, u8, &.{ home, "/installed.txt" });
        errdefer allocator.free(installed);
        const lockfile = try std.mem.concat(allocator, u8, &.{ home, "/thottam.lock" });
        errdefer allocator.free(lockfile);
        const files = try std.mem.concat(allocator, u8, &.{ home, "/thottam.files" });

        return .{
            .home = home,
            .outside = outside,
            .config = .{
                .home = home,
                .org = "https://github.com/kaappi",
                .lib_dir = lib_dir,
                .src_dir = src_dir,
                .installed = installed,
                .lockfile = lockfile,
                .files = files,
            },
        };
    }

    /// The hostile name: a traversal out of `config.src_dir` that lands on
    /// `outside`. joinPath is literal concatenation, so this is exactly the
    /// shape that escaped $KAAPPI_HOME before the read paths were guarded.
    fn hostileName(self: TmpHome, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "../../{s}", .{std.fs.path.basename(self.outside)});
    }

    fn deinit(self: *TmpHome, allocator: std.mem.Allocator) void {
        thottam.removeDir(allocator, self.home) catch {};
        thottam.removeDir(allocator, self.outside) catch {};
        allocator.free(self.config.lib_dir);
        allocator.free(self.config.src_dir);
        allocator.free(self.config.installed);
        allocator.free(self.config.lockfile);
        allocator.free(self.config.files);
        allocator.free(self.home);
        allocator.free(self.outside);
    }
};

test "doList omits a state-file name that escapes $KAAPPI_HOME (issue #2144)" {
    const allocator = std.testing.allocator;
    var env = try TmpHome.init(allocator, "list");
    defer env.deinit(allocator);
    const evil = try env.hostileName(allocator);
    defer allocator.free(evil);

    // A hand-edited installed.txt: one real package, one traversal.
    const content = try std.fmt.allocPrint(allocator, "kaappi-good\n{s}\n", .{evil});
    defer allocator.free(content);
    try thottam.writeFile(allocator, env.config.installed, content);

    const cap = try captureOutput(false, thottam.doList, .{ allocator, env.config });
    defer allocator.free(cap.out);
    try std.testing.expect(cap.err == null);
    // The good name is listed; the hostile line never reaches the output —
    // nor joinPath, which for that name points outside $KAAPPI_HOME.
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "kaappi-good") != null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "../") == null);
}

test "doVerify reports a hostile lockfile name as corruption and fails (issue #2144)" {
    const allocator = std.testing.allocator;
    var env = try TmpHome.init(allocator, "vlock");
    defer env.deinit(allocator);
    const evil = try env.hostileName(allocator);
    defer allocator.free(evil);

    // A hostile lockfile line and nothing installed: before the name check
    // this line was structurally sound (non-empty name, non-empty SHA) and
    // verify exited clean without ever noticing the name.
    const line = try std.fmt.allocPrint(allocator, "{s} deadbeef\n", .{evil});
    defer allocator.free(line);
    try thottam.writeFile(allocator, env.config.lockfile, line);

    const cap = try captureOutput(false, thottam.doVerify, .{ allocator, env.config });
    defer allocator.free(cap.out);
    try std.testing.expectEqual(@as(?anyerror, error.VerifyFailed), cap.err);
    // Rejected loudly, naming the offending line.
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "MALFORMED") != null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, evil) != null);
}

test "doVerify reports a hostile installed.txt name as corruption, not a lockfile finding (issue #2144)" {
    const allocator = std.testing.allocator;
    var env = try TmpHome.init(allocator, "vinst");
    defer env.deinit(allocator);
    const evil = try env.hostileName(allocator);
    defer allocator.free(evil);

    // Structurally sound lockfile; the hostile name arrives via installed.txt.
    try thottam.writeFile(allocator, env.config.lockfile, "kaappi-good abc123def456\n");
    const content = try std.fmt.allocPrint(allocator, "{s}\n", .{evil});
    defer allocator.free(content);
    try thottam.writeFile(allocator, env.config.installed, content);

    const cap = try captureOutput(false, thottam.doVerify, .{ allocator, env.config });
    defer allocator.free(cap.out);
    try std.testing.expectEqual(@as(?anyerror, error.VerifyFailed), cap.err);
    // Before the guard the name was joined onto src_dir for getPkgSha and
    // the line reported as a missing lockfile entry; now it is named as
    // corruption before any path is built from it.
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "MALFORMED") != null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, evil) != null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "no lockfile entry") == null);
}

test "doUpdate rejects a hostile name given on the command line (issue #2144)" {
    const allocator = std.testing.allocator;
    var env = try TmpHome.init(allocator, "uarg");
    defer env.deinit(allocator);
    const evil = try env.hostileName(allocator);
    defer allocator.free(evil);

    const cap = try captureOutput(true, thottam.doUpdate, .{ allocator, env.config, evil });
    defer allocator.free(cap.out);
    // The same entry guard as install/remove: loud, naming the package.
    try std.testing.expectEqual(@as(?anyerror, error.InvalidPackageName), cap.err);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "invalid package name") != null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, evil) != null);
}

test "doUpdate of every package skips hostile names read back from installed.txt (issue #2144)" {
    const allocator = std.testing.allocator;
    var env = try TmpHome.init(allocator, "uall");
    defer env.deinit(allocator);
    const evil = try env.hostileName(allocator);
    defer allocator.free(evil);

    const content = try std.fmt.allocPrint(allocator, "{s}\n", .{evil});
    defer allocator.free(content);
    try thottam.writeFile(allocator, env.config.installed, content);

    const no_pkg: ?[]const u8 = null;
    const cap = try captureOutput(true, thottam.doUpdate, .{ allocator, env.config, no_pkg });
    defer allocator.free(cap.out);
    try std.testing.expect(cap.err == null);
    // The escaped directory exists (TmpHome creates it as a plain non-repo),
    // so pre-guard code announced the package and ran git in that directory;
    // the guard skips the line instead. Nothing is announced, nothing runs.
    try std.testing.expect(std.mem.indexOf(u8, cap.out, evil) == null);
    try std.testing.expect(std.mem.indexOf(u8, cap.out, "../") == null);
}
