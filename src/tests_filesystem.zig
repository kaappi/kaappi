const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "file-info returns file-info object" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(file-info? (file-info \".\" #t))"));
}

test "file-info:size returns non-negative fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (file-info:size (file-info \".\" #t)) 0)"));
}

test "file-info:inode returns positive fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (file-info:inode (file-info \".\" #t)) 0)"));
}

test "file-info:nlinks returns positive fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (file-info:nlinks (file-info \".\" #t)) 0)"));
}

test "file-info:device returns fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(integer? (file-info:device (file-info \".\" #t)))"));
}

test "file-info:uid and :gid return fixnums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(integer? (file-info:uid (file-info \".\" #t)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(integer? (file-info:gid (file-info \".\" #t)))"));
}

test "file-info:atime and :ctime return fixnums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (file-info:atime (file-info \".\" #t)) 0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (file-info:ctime (file-info \".\" #t)) 0)"));
}

test "file-info:blksize and :blocks" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (file-info:blksize (file-info \".\" #t)) 0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (file-info:blocks (file-info \".\" #t)) 0)"));
}

test "file-info predicates on directory" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(file-info-directory? (file-info \".\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-regular? (file-info \".\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-symlink? (file-info \".\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-fifo? (file-info \".\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-socket? (file-info \".\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-device? (file-info \".\" #t))"));
}

test "file-info on regular file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(file-info-regular? (file-info \"build.zig\" #t))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-info-directory? (file-info \"build.zig\" #t))"));
}

test "pid returns positive integer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (pid) 0)"));
}

test "current-directory returns non-empty string" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (current-directory))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (string-length (current-directory)) 0)"));
}

test "umask returns non-negative integer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (umask) 0)"));
}

test "user-uid and user-gid return fixnums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (user-uid) 0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (user-gid) 0)"));
}

test "user-effective-uid and user-effective-gid" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (user-effective-uid) 0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (user-effective-gid) 0)"));
}

test "user-supplementary-gids returns list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(list? (user-supplementary-gids))"));
}

test "real-path resolves current directory" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (real-path \".\"))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (string-length (real-path \".\")) 0)"));
}

test "user-info for current user" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(user-info? (user-info (user-uid)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (user-info:name (user-info (user-uid))))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= (user-info:uid (user-info (user-uid))) (user-uid))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (user-info:home-dir (user-info (user-uid))))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (user-info:shell (user-info (user-uid))))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (user-info:full-name (user-info (user-uid))))"));
}

test "user-info by name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(let ((ui (user-info (user-uid))))
        \\  (user-info? (user-info (user-info:name ui))))
    ));
}

test "user-info? predicate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(user-info? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(user-info? \"hello\")"));
}

test "group-info for current group" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(group-info? (group-info (user-gid)))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(string? (group-info:name (group-info (user-gid))))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(= (group-info:gid (group-info (user-gid))) (user-gid))"));
}

test "group-info? predicate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(group-info? 42)"));
}

test "directory-files returns list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(list? (directory-files \".\"))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (length (directory-files \".\")) 0)"));
}

test "open-directory read-directory close-directory cycle" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(let ((d (open-directory ".")))
        \\  (let ((first (read-directory d)))
        \\    (close-directory d)
        \\    (string? first)))
    ));
}

test "terminal? on file port returns #f" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval(
        \\(let ((p (open-input-file "build.zig")))
        \\  (let ((result (terminal? p)))
        \\    (close-input-port p)
        \\    result))
    ));
}

test "set-environment-variable! and get-environment-variable roundtrip" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(begin
        \\  (set-environment-variable! "KAAPPI_TEST_ENV" "hello42")
        \\  (equal? (get-environment-variable "KAAPPI_TEST_ENV") "hello42"))
    ));
}

test "delete-environment-variable! removes variable" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(begin
        \\  (set-environment-variable! "KAAPPI_TEST_DEL" "val")
        \\  (delete-environment-variable! "KAAPPI_TEST_DEL")
        \\  (not (get-environment-variable "KAAPPI_TEST_DEL")))
    ));
}

test "posix-time returns reasonable epoch seconds" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(> (posix-time) 1700000000)"));
}

test "monotonic-time returns non-negative" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= (monotonic-time) 0)"));
}

test "rename-file works" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(begin
        \\  (call-with-output-file "/tmp/kaappi-rename-test"
        \\    (lambda (p) (display "data" p)))
        \\  (rename-file "/tmp/kaappi-rename-test" "/tmp/kaappi-rename-test2")
        \\  (let ((exists (file-exists? "/tmp/kaappi-rename-test2")))
        \\    (delete-file "/tmp/kaappi-rename-test2")
        \\    exists))
    ));
}

test "set-file-mode changes permissions" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(begin
        \\  (call-with-output-file "/tmp/kaappi-chmod-test"
        \\    (lambda (p) (display "data" p)))
        \\  (set-file-mode "/tmp/kaappi-chmod-test" #o644)
        \\  (let ((mode (file-info:mode (file-info "/tmp/kaappi-chmod-test" #t))))
        \\    (delete-file "/tmp/kaappi-chmod-test")
        \\    (= (modulo mode #o10000) #o644)))
    ));
}
