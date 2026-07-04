pub const conditionals = @import("compiler_conditionals.zig");
pub const bindings = @import("compiler_bindings.zig");
pub const advanced = @import("compiler_advanced.zig");
pub const lambda = @import("compiler_lambda.zig");

// Re-export all public functions so existing callers don't break

// Conditional forms
pub const compileAnd = conditionals.compileAnd;
pub const compileOr = conditionals.compileOr;
pub const compileWhen = conditionals.compileWhen;
pub const compileUnless = conditionals.compileUnless;
pub const compileCond = conditionals.compileCond;
pub const compileCondBody = conditionals.compileCondBody;
pub const compileCondExpand = conditionals.compileCondExpand;
pub const evalFeatureReq = conditionals.evalFeatureReq;
pub const emitArrowCall = conditionals.emitArrowCall;

// Binding and iteration forms
pub const compileLet = bindings.compileLet;
pub const compileLetStar = bindings.compileLetStar;
pub const compileLetrec = bindings.compileLetrec;
pub const compileLetrecStar = bindings.compileLetrecStar;
pub const compileNamedLet = bindings.compileNamedLet;
pub const compileDo = bindings.compileDo;
pub const compileLetBody = bindings.compileLetBody;
pub const compileBodyForms = lambda.compileBodyForms;
pub const compileLetValues = bindings.compileLetValues;
pub const compileLetStarValues = bindings.compileLetStarValues;
pub const buildLetValues = bindings.buildLetValues;

// Advanced forms
pub const compileGuard = advanced.compileGuard;
pub const appendToList = advanced.appendToList;
pub const compileCase = advanced.compileCase;
pub const compileCaseLambda = advanced.compileCaseLambda;
pub const compileQuasiquote = advanced.compileQuasiquote;
pub const compileParameterize = advanced.compileParameterize;
