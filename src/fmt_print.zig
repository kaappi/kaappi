//! The layout engine for `kaappi fmt` (kaappi#1518). Walks the CST built by
//! `fmt.zig` and emits canonical text: 2-space R7RS indentation, single spaces
//! between elements, closing parens gathered, and forms reflowed to fit
//! `max_width` columns.
//!
//! **Fits-or-breaks.** Every list is first measured; if it renders within the
//! width on one line it is emitted inline (this is what gathers parens and
//! collapses spacing). Otherwise it breaks, using one of two well-known Scheme
//! layouts chosen from its operator:
//!
//!   * **body style** (`define`, `lambda`, `let`, `when`, `case`, …): a fixed
//!     number of *distinguished* subforms stay on the operator's line; the rest
//!     — the body — go one per line, indented two spaces from the open paren.
//!   * **call style** (function calls, `cond`, `and`, vectors, unknown heads):
//!     the first argument stays on the operator's line and the rest align under
//!     it. This is the Emacs/`scmindent` default and the natural look for calls.
//!
//! **Comments and blank lines.** A line comment forces its list to break and
//! keeps the closing paren off its line. A comment on the same source line as
//! the preceding datum stays trailing; on its own line it leads the next datum.
//! A single blank line between body items or top-level forms is preserved (runs
//! collapse to one); everything else about layout is recomputed, which is what
//! makes the output canonical.
//!
//! **Idempotence** rests on `measure` and the inline emitter agreeing exactly on
//! width, and on layout depending only on content — never on the input's own line
//! breaks (comments aside). Both are covered by tests in `tests_fmt.zig`.

const std = @import("std");
const fmt = @import("fmt.zig");

const Node = fmt.Node;
const NodeKind = fmt.NodeKind;

/// Target line width. Forms whose one-line rendering would exceed this break.
pub const max_width: usize = 80;
const indent_step: usize = 2;

/// Render a top-level node sequence to a canonical, arena-allocated string
/// ending in exactly one newline (empty input yields an empty string).
pub fn print(arena: std.mem.Allocator, nodes: []Node) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(arena);
    var p = Printer{ .out = &out, .a = arena };
    try p.emitTopLevel(nodes);
    if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(arena, '\n');
    return out.toOwnedSlice(arena);
}

const Printer = struct {
    out: *std.ArrayList(u8),
    a: std.mem.Allocator,
    /// Column (byte offset since the last newline) of the write cursor.
    col: usize = 0,
    /// The current line ends in a line comment, so nothing more may be appended
    /// to it — the next token, and any closing paren, must start a new line.
    line_comment_open: bool = false,

    fn raw(self: *Printer, s: []const u8) error{OutOfMemory}!void {
        try self.out.appendSlice(self.a, s);
        if (std.mem.lastIndexOfScalar(u8, s, '\n')) |nl| {
            self.col = s.len - nl - 1;
        } else {
            self.col += s.len;
        }
        self.line_comment_open = false;
    }

    fn spaces(self: *Printer, n: usize) error{OutOfMemory}!void {
        try self.out.appendNTimes(self.a, ' ', n);
        self.col += n;
    }

    fn newlineTo(self: *Printer, indent: usize) error{OutOfMemory}!void {
        try self.out.append(self.a, '\n');
        try self.out.appendNTimes(self.a, ' ', indent);
        self.col = indent;
        self.line_comment_open = false;
    }

    /// Emit an empty line (used to preserve a single blank line of grouping).
    fn blankLine(self: *Printer) error{OutOfMemory}!void {
        try self.out.append(self.a, '\n');
    }

    // ── Top level ────────────────────────────────────────────────────────────

    fn emitTopLevel(self: *Printer, nodes: []Node) error{OutOfMemory}!void {
        for (nodes, 0..) |*node, i| {
            if (i > 0) {
                if (isComment(node.kind) and node.newlines_before == 0 and !self.line_comment_open) {
                    // A comment on the same line as the previous form's close.
                    try self.spaces(1);
                    try self.emitNode(node);
                    continue;
                }
                if (node.newlines_before >= 2) try self.blankLine();
                try self.newlineTo(0);
            }
            try self.emitNode(node);
        }
    }

    // ── Node dispatch ────────────────────────────────────────────────────────

    fn emitNode(self: *Printer, node: *Node) error{OutOfMemory}!void {
        switch (node.kind) {
            .atom, .block_comment => try self.raw(node.text),
            .line_comment => {
                try self.raw(node.text);
                self.line_comment_open = true;
            },
            .prefix => {
                try self.raw(node.text);
                try self.emitNode(&node.children[0]);
            },
            .datum_comment => {
                try self.raw("#;");
                try self.emitNode(&node.children[0]);
            },
            .list => try self.emitList(node),
        }
    }

    fn emitList(self: *Printer, node: *Node) error{OutOfMemory}!void {
        const start_col = self.col;
        // Inline only when it fits *and* holds no blank line that layout would
        // preserve (see `hasBodyBlank`) — collapsing such a form would silently
        // drop the author's grouping and, worse, break idempotence.
        if (measure(node)) |w| {
            if (start_col + w <= max_width and !hasBodyBlank(node)) return self.emitInline(node);
        }
        try self.emitBrokenList(node, start_col);
    }

    /// One-line rendering: `(` elements-joined-by-single-space `)`. Only called
    /// when `measure` proved the node inline-able, so it must produce exactly
    /// `measure(node)` bytes — the two are kept in lockstep for idempotence.
    fn emitInline(self: *Printer, node: *Node) error{OutOfMemory}!void {
        switch (node.kind) {
            .atom, .block_comment, .line_comment => try self.raw(node.text),
            .prefix => {
                try self.raw(node.text);
                try self.emitInline(&node.children[0]);
            },
            .datum_comment => {
                try self.raw("#;");
                try self.emitInline(&node.children[0]);
            },
            .list => {
                try self.raw(node.text); // open delimiter
                for (node.children, 0..) |*child, i| {
                    if (i > 0) try self.spaces(1);
                    try self.emitInline(child);
                }
                try self.raw(")");
            },
        }
    }

    // ── Broken (multi-line) lists ────────────────────────────────────────────

    fn emitBrokenList(self: *Printer, node: *Node, start_col: usize) error{OutOfMemory}!void {
        try self.raw(node.text); // open delimiter
        const open_col = self.col; // column just inside the delimiter

        const op_idx = firstCodeIndex(node.children);
        if (op_idx == null or op_idx.? != 0 or node.is_data) {
            // No operator to hug (empty-but-broken, a leading comment, or a data
            // vector): lay every element out vertically under the open column.
            try self.emitVertical(node.children, open_col);
            return self.closeParen(node, start_col);
        }

        switch (styleOf(node)) {
            .body => |n| try self.emitBodyStyle(node, start_col, n),
            .call => try self.emitCallStyle(node, open_col),
        }
        try self.closeParen(node, start_col);
    }

    /// Body style: operator plus `n` distinguished subforms share the first line;
    /// the remaining children are the body, one per line at `open+2`.
    fn emitBodyStyle(self: *Printer, node: *Node, start_col: usize, n: usize) error{OutOfMemory}!void {
        const children = node.children;
        var placed: usize = 0; // code items on line 1 (operator counts as one)
        var i: usize = 0;
        while (i < children.len and placed <= n) {
            if (isComment(children[i].kind)) break; // a leading comment starts the body
            if (placed > 0) try self.spaces(1);
            try self.emitNode(&children[i]);
            placed += 1;
            i += 1;
            // Trailing same-line comments ride along on the first line.
            while (i < children.len and isComment(children[i].kind) and children[i].newlines_before == 0) {
                try self.spaces(1);
                try self.emitNode(&children[i]);
                const was_line = children[i].kind == .line_comment;
                i += 1;
                if (was_line) {
                    try self.emitBody(children[i..], start_col + indent_step);
                    return;
                }
            }
        }
        try self.emitBody(children[i..], start_col + indent_step);
    }

    /// Call style: the first argument stays on the operator's line; later
    /// arguments align under it.
    fn emitCallStyle(self: *Printer, node: *Node, open_col: usize) error{OutOfMemory}!void {
        const children = node.children;
        try self.emitNode(&children[0]); // operator, already at open_col
        var i: usize = 1;

        // Trailing same-line comments after the operator.
        while (i < children.len and isComment(children[i].kind) and children[i].newlines_before == 0) {
            try self.spaces(1);
            try self.emitNode(&children[i]);
            if (children[i].kind == .line_comment) {
                i += 1;
                return self.emitBody(children[i..], open_col);
            }
            i += 1;
        }

        if (i < children.len and !isComment(children[i].kind)) {
            try self.spaces(1);
            const align_col = self.col; // column where the first argument begins
            try self.emitNode(&children[i]);
            i += 1;
            while (i < children.len and isComment(children[i].kind) and children[i].newlines_before == 0) {
                try self.spaces(1);
                try self.emitNode(&children[i]);
                if (children[i].kind == .line_comment) {
                    i += 1;
                    return self.emitBody(children[i..], align_col);
                }
                i += 1;
            }
            return self.emitBody(children[i..], align_col);
        }
        // Operator with no argument on its line (only comments follow).
        try self.emitBody(children[i..], open_col);
    }

    /// Every child on its own line at `indent` (used for vectors and the
    /// leading-comment fallback).
    fn emitVertical(self: *Printer, children: []Node, indent: usize) error{OutOfMemory}!void {
        try self.emitBodyFrom(children, indent, true);
    }

    /// Body items each on their own line at `indent`, with a fresh line before
    /// the first (it drops off the operator's line).
    fn emitBody(self: *Printer, children: []Node, indent: usize) error{OutOfMemory}!void {
        try self.emitBodyFrom(children, indent, false);
    }

    fn emitBodyFrom(self: *Printer, children: []Node, indent: usize, first_inline: bool) error{OutOfMemory}!void {
        var started = false;
        for (children) |*child| {
            const on_own_line = !(first_inline and !started);
            if (isComment(child.kind) and child.newlines_before == 0 and started and !self.line_comment_open) {
                // Trailing comment on the previous item's line.
                try self.spaces(1);
                try self.emitNode(child);
                continue;
            }
            if (on_own_line) {
                // Preserve a single blank line of grouping before any own-line
                // item, including the first (the item after the operator line).
                if (child.newlines_before >= 2) try self.blankLine();
                try self.newlineTo(indent);
            }
            try self.emitNode(child);
            started = true;
        }
    }

    /// Emit the closing paren, gathered onto the current line unless a trailing
    /// line comment has closed it (then it drops to a fresh line under the open).
    fn closeParen(self: *Printer, node: *Node, paren_col: usize) error{OutOfMemory}!void {
        _ = node;
        if (self.line_comment_open) try self.newlineTo(paren_col);
        try self.raw(")");
    }
};

// ── Measurement ──────────────────────────────────────────────────────────────

/// Inline width of `node` in bytes, or null if it cannot be one line (contains a
/// line comment, a multi-line block comment, or an atom with an embedded
/// newline). Memoised on the node so repeated fit checks stay linear.
fn measure(node: *Node) ?usize {
    if (node.width_computed) return node.inline_width;
    const w = computeMeasure(node);
    node.width_computed = true;
    node.inline_width = w;
    return w;
}

fn computeMeasure(node: *Node) ?usize {
    switch (node.kind) {
        .line_comment => return null,
        .atom, .block_comment => {
            if (std.mem.indexOfScalar(u8, node.text, '\n') != null) return null;
            return node.text.len;
        },
        .prefix => {
            const child = measure(&node.children[0]) orelse return null;
            return node.text.len + child;
        },
        .datum_comment => {
            const child = measure(&node.children[0]) orelse return null;
            return 2 + child; // "#;" glued to its datum
        },
        .list => {
            var total: usize = node.text.len + 1; // open delimiter + ")"
            for (node.children, 0..) |*child, i| {
                const w = measure(child) orelse return null;
                total += w;
                if (i > 0) total += 1; // separating space
            }
            return total;
        },
    }
}

// ── Layout rules ─────────────────────────────────────────────────────────────

const Style = union(enum) {
    /// Function-call / data layout: first argument on the head line, rest aligned
    /// under it.
    call,
    /// Special-form layout: `n` distinguished subforms on the head line, body at
    /// open+2.
    body: usize,
};

/// True when the list holds a blank line that layout will preserve — i.e. a
/// blank before a child that lands on its own line (a body item, or a vector
/// element past the first). Blanks before the operator or a distinguished
/// subform sit on the head line and are dropped, so they do not count; keeping
/// this in lockstep with what `emitBodyFrom` actually emits is what makes
/// formatting idempotent (a preserved blank re-forces the break next time; a
/// dropped one does not resurrect it).
fn hasBodyBlank(node: *Node) bool {
    if (node.kind != .list) return false;
    const children = node.children;
    const op_idx = firstCodeIndex(children);
    const first_body: usize = if (op_idx == null or op_idx.? != 0 or node.is_data)
        1 // vertical layout: only the first element shares the open line
    else switch (styleOf(node)) {
        .body => |n| n + 1, // operator + n distinguished subforms on the head line
        .call => 2, // operator + first argument on the head line
    };
    if (first_body >= children.len) return false;
    for (children[first_body..]) |child| {
        if (child.newlines_before >= 2) return true;
    }
    return false;
}

fn styleOf(node: *Node) Style {
    const op = node.children[0];
    if (op.kind != .atom) return .call;
    const name = op.text;

    if (std.mem.eql(u8, name, "let")) {
        // Named let — `(let loop ((…)) body)` — has an extra distinguished form.
        if (node.children.len >= 2 and node.children[1].kind == .atom) return .{ .body = 2 };
        return .{ .body = 1 };
    }
    if (bodyDistinguished(name)) |n| return .{ .body = n };
    return .call;
}

/// Distinguished-subform count for the well-known body-style forms, or null for
/// anything laid out as a call. Covers the R7RS special forms plus a few common
/// macros (SRFI-64 `test-group`, SRFI-8 `receive`) whose bodies read as blocks.
fn bodyDistinguished(name: []const u8) ?usize {
    const table = [_]struct { name: []const u8, n: usize }{
        .{ .name = "lambda", .n = 1 },
        .{ .name = "define", .n = 1 },
        .{ .name = "define-values", .n = 1 },
        .{ .name = "define-syntax", .n = 1 },
        .{ .name = "define-record-type", .n = 1 },
        .{ .name = "define-library", .n = 1 },
        .{ .name = "let*", .n = 1 },
        .{ .name = "letrec", .n = 1 },
        .{ .name = "letrec*", .n = 1 },
        .{ .name = "let-values", .n = 1 },
        .{ .name = "let*-values", .n = 1 },
        .{ .name = "let-syntax", .n = 1 },
        .{ .name = "letrec-syntax", .n = 1 },
        .{ .name = "when", .n = 1 },
        .{ .name = "unless", .n = 1 },
        .{ .name = "begin", .n = 0 },
        .{ .name = "case", .n = 1 },
        .{ .name = "do", .n = 2 },
        .{ .name = "parameterize", .n = 1 },
        .{ .name = "guard", .n = 1 },
        .{ .name = "syntax-rules", .n = 1 },
        .{ .name = "case-lambda", .n = 0 },
        .{ .name = "receive", .n = 2 },
        .{ .name = "test-group", .n = 1 },
        .{ .name = "test-group-with-cleanup", .n = 1 },
    };
    for (table) |e| {
        if (std.mem.eql(u8, name, e.name)) return e.n;
    }
    return null;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn isComment(kind: NodeKind) bool {
    return kind == .line_comment or kind == .block_comment;
}

/// Index of the first non-comment child, or null if there is none.
fn firstCodeIndex(children: []Node) ?usize {
    for (children, 0..) |c, i| {
        if (!isComment(c.kind)) return i;
    }
    return null;
}
