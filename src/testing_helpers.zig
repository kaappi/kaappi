const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
pub const VM = vm_mod.VM;
pub const VMError = vm_mod.VMError;
pub const Value = types.Value;

pub fn makeTestVM(gc: *memory.GC) !VM {
    var vm = try VM.init(gc);
    memory.setGCInstance(gc);
    try primitives_mod.registerAll(&vm);
    try library_mod.registerStandardLibraries(&vm.libraries, vm.globals);
    return vm;
}
