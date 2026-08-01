window.BENCHMARK_DATA = {
  "lastUpdate": 1785606558484,
  "repoUrl": "https://github.com/kaappi/kaappi",
  "entries": {
    "Benchmark": [
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "34774bf4d0fcc48e24962a275b66bd16ba1fadc1",
          "message": "Reserve begin-internal define-syntax names during lowering, fixing #1772 (#1823)\n\nA literal begin used outside real top level or a macro-expansion result\n(e.g. a non-first body form, or an if branch) lowered every child eagerly\nvia ir.lowerBegin before any of them compiled. A define-syntax sibling's\nregistration into the macro table is a side effect of *compiling* its\nnode, not of lowering it, so a later sibling lowered in the same pass\nnever saw it via lookupMacro — its macro use compiled as a plain call to\nan unbound global instead of deferring to real expansion.\n\nlowerBegin now reserves a literal define-syntax sibling's name the\nmoment its form is reached, before lowering the next sibling, mirroring\nhow compiler_lambda.scanBodyDefs already resolves the identical problem\nfor a body's own leading definitions. The reservation never overwrites a\nname already visible (a real transformer from this scope or an\nenclosing one), and rolls itself back if a later sibling fails to lower.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T19:40:56Z",
          "tree_id": "6528211d11615f606389a4c3312c373bc4937acf",
          "url": "https://github.com/kaappi/kaappi/commit/34774bf4d0fcc48e24962a275b66bd16ba1fadc1"
        },
        "date": 1785270241401,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.350526,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.173684,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.601917,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.039383,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006335,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057487,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.574898,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.247229,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612498,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.443902,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811295,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65011,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043621,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8dbe0342812f417582aba85e9cbb9289eab62945",
          "message": "Resolve a macro's def-env-bound free references through their own library (#1824)\n\n* Resolve a macro's def-env-bound free references through their own library, fixing issue #1812\n\nA macro's free reference to a name its own defining library binds (exported\nor not) previously resolved by bare name against the use site's mutable\nglobals table: a procedure reference was left completely unrenamed, and a\nnon-procedure reference was only protected against lexical (let/lambda)\nshadowing at the use site, not against a genuine top-level redefinition of\nthe same name — since that protection still read the importer's own\nvm.globals at the injected instruction's execution time. An unrelated\ntop-level `(define helper2 ...)` in the importing file could silently\ncorrupt an already-imported macro's expansion.\n\nGeneralizes #1715's `__kaappi_base__` mechanism (routing a compiler-\nsynthesized reference through a stable registry instead of vm.globals) to a\nnew, per-transformer `__kaappi_defenv__<libname>\\x1f<origname>` prefix that\nget_global/call_global/set_global resolve through that specific library's\nown environment at runtime — never touching the use site's globals table for\nthese names. Values stay unbaked (a plain symbol, not a `load_const`\nconstant): embedding a resolved Closure/NativeFn as a bytecode constant\nsilently downgrades to nil on a `.sbc` cache round-trip, the same mistake\n#1715's own first draft made and abandoned.\n\nExcludes true `(scheme base)` bindings merely re-exported by a library\n(call-with-values, raise-continuable, with-exception-handler, etc.) from the\nnew mechanism — several compiler spots (compileCallWithValuesTail's is_tail\ndispatch, chief among them) recognize these by exact bare name, and a real\nregression in SRFI 248's guard macro during development confirmed the\ntail-call dispatch silently breaks otherwise. Also teaches\ntypes.stripHygienicPrefix to recognize the new prefix alongside the existing\n__hyg_ one, fixing two more real regressions found the same way: SRFI 41's\nstream-match (a macro whose template defines another macro via\nletrec-syntax, which must not re-wrap an already-prefixed reference) and\nSRFI 211's define-macro (whose lisp-transformer/er-macro-transformer\nkeywords are SRFI 211 primitives, not scheme-base ones, so the scheme-base\nexclusion alone didn't cover them).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Also exclude tail_call_global from caching a def-env resolution (#1812 follow-up)\n\nget_global/call_global/set_global were each guarded against caching a\n__kaappi_defenv__-prefixed resolution (self.global_version doesn't catch a\nlibrary's own internal set! on its def_env), but tail_call_global — the\ntail-position counterpart of call_global, populating the same\nfunc.global_cache from the same lookupGlobalLocked — was missed. Found by\nre-auditing every func.global_cache populate site after rebasing onto\n#1817, which touches the same cache machinery in call_global/\ntail_call_global.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T19:40:43Z",
          "tree_id": "36f1f193e53db828f51b426e2e197fb87baba200",
          "url": "https://github.com/kaappi/kaappi/commit/8dbe0342812f417582aba85e9cbb9289eab62945"
        },
        "date": 1785270935355,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.351355,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.268028,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578822,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.008159,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006351,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046924,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315281,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057326,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.46505,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.251948,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605648,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435969,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79819,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.692177,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044675,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3d9dae15ac0bbac2e74ceae16cfc0fe3ebfdd754",
          "message": "Drop stale cross-thread concurrency limitation docs, fixing #1793 (#1825)\n\nREADME.md, lib/kaappi/parallel.sld, and benchmarks/gate/ still described\n#1487, #1489, and #1520 as open -- all three were fixed 2026-07-13/14/15\nand have regression tests. This understated a working feature (README\ntold readers not to use cross-thread channels in production) and left\nthe gate harness's self-containment rationale reading like a live engine\nbug report instead of a completed benchmark's historical protocol note.\n\nReplaced the stale caveats with the constraint that's actually still\ntrue: a channel (or a pool containing one) must reach the other thread\nthrough lexical capture in the thunk, not a shared top-level define\n(#1742).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T20:42:48Z",
          "tree_id": "a683312c38023a86fa062019aafd848220761197",
          "url": "https://github.com/kaappi/kaappi/commit/3d9dae15ac0bbac2e74ceae16cfc0fe3ebfdd754"
        },
        "date": 1785274549326,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.034926,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.42476,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572354,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.880802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006715,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045598,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302395,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055591,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.373733,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.190613,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.559658,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47289,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.730701,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704533,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045445,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d9c38fefd0443641edb311d0cb49f05af9354c6",
          "message": "Split src/types.zig into 11 domain files, fixing #1731 (#1827)\n\ntypes.zig had grown to 1871 lines (already 1605 before #1730, both over\nthe 1500-line policy), one heap-type addition at a time across 105\ncommits. Splits struct/enum definitions by domain (types_ffi.zig,\ntypes_port.zig, types_continuation.zig, ...) while types.zig re-exports\nevery name (`pub const Foo = types_x.Foo;`), so the dozens of existing\n`types.Foo` call sites across primitives_*.zig, vm*.zig, gc_collect.zig,\ngc_deep_copy.zig, and printer.zig need no changes. Object.expectedTag()'s\nswitch is also untouched — it already referenced bare names, which now\nresolve through the re-export aliases.\n\ntypes.zig drops to ~1200 lines; each new file is 35-190 lines. Verified\nwith zig build, zig build test, the full Scheme suite (2008 pass), and\nzig build test -Dgc-stress=true, per the issue's own re-verification\nchecklist for the GC mark/sweep switches.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T21:12:31Z",
          "tree_id": "311a2f08ec9f5cbf0f3e0bd9c60a43262728ebfe",
          "url": "https://github.com/kaappi/kaappi/commit/5d9c38fefd0443641edb311d0cb49f05af9354c6"
        },
        "date": 1785275449153,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.774613,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.015899,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.543421,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.667183,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006797,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044669,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.286428,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054396,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.679593,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.085522,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.489511,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.404505,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.637716,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.939072,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040679,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55e1bf32cd510d33f21db3c28dac84b5c3b25ca0",
          "message": "Bypass ReleaseSafe allocator 0xAA fill on hot, size-proportional buffers (#1830)\n\n* Bypass the ReleaseSafe allocator fill for GC object payload buffers\n\nZig 0.16's std.mem.Allocator.alloc/.free/.dupe unconditionally\nmemset(..., 0xAA) new and freed memory in ReleaseSafe, inside their\nown generic bodies rather than the vtable functions they call into.\nThis makes the fill unavoidable via a backing-allocator swap or\n@setRuntimeSafety(false) at the call site (confirmed by disassembly)\n- the only way around it is to call rawAlloc/rawFree directly.\n\nAdd allocSliceNoFill/freeSliceNoFill/dupeSliceNoFill to memory.zig\nand use them for every GC object's variable-length payload: vector,\nstring, and bytevector data, closure/native-closure upvalues, record\ninstance fields, continuation backing buffers, multiple-values\narrays, hash table entries (including rehash's growth), numeric\nvectors, and fiber register/frame arrays. Both the constructors in\nmemory.zig and the matching frees in gc_collect.zig's freeObject are\nconverted together, since a mismatched pair would silently keep\npaying the tax on whichever end was missed.\n\nKaappi's own Debug-mode poisoning, FREED_OWNER stamping, and\ngc-stress quarantine are unaffected - they're implemented\nindependently of whatever the underlying allocator does.\n\n* Bypass the ReleaseSafe allocator fill for bignum arithmetic buffers\n\nEvery bignum add/sub/mul/quotient/remainder allocates a scratch\nlimbs buffer, uses it briefly, then frees it - paying the\nalloc-fill and free-fill back to back on every operation. Convert\naddMagnitude/subMagnitude/mulMagnitude/divMagnitudeBySingleLimb/\ndivMagnitudeMulti and their call sites, plus the bignum-to-string\ndupe sites, to the allocSliceNoFill/freeSliceNoFill/dupeSliceNoFill\nhelpers from memory.zig.\n\nparseBignumString is deliberately left alone: it's a cold,\nnumber-literal-parsing path (not the arithmetic hot loop) built\naround realloc, which would need a fourth helper for one path that\ndoesn't earn it.\n\n* Bypass the ReleaseSafe allocator fill for VM growth and call/cc capture\n\nensureFrameCapacity/ensureRegisterCapacity double the register file\nand call frame stack on overflow, copying live data into a fresh\nbuffer before freeing the old one - both ends were paying the\nallocator fill. captureContinuation's scratch SavedFrame buffer is\nsimilar: allocated, copied into the continuation's own backing\nbuffer, and immediately freed.\n\nvm_continuations.zig didn't previously import memory.zig directly\n(it only reached it transitively through vm.zig, which doesn't\nre-export it), so add that import alongside the two converted call\nsites.\n\n* Bypass the ReleaseSafe allocator fill for string/bytevector builders\n\nTwo recurring shapes in these files pay the allocator fill: a\nmutation primitive (string-set!, string-copy!, string-fill!) that\nrebuilds and frees a string's backing buffer when the new content's\nUTF-8 byte width changes, and a \"double-alloc\" builder pattern where\na primitive fills a scratch buffer and immediately hands it to\ngc.allocString/allocBytevector, which copies it again. Convert both\nshapes wherever the buffer size is proportional to the string or\nbytevector being built, across string, make-string, list->string,\nstring-set!, string-copy!, string-fill!, string->list's >4096\ncodepoint fallback, string->vector, the SRFI-13 join/concatenate/pad/\nreverse/replace family, and the bytevector constructor, append, and\nread-bytevector paths.\n\n* Bypass the ReleaseSafe allocator fill for vector builders\n\nSame double-alloc builder pattern as the string/bytevector\nprimitives: list->vector, vector-append, vector->string,\nvector-reverse-copy, vector-unfold(-right), vector-concatenate,\nvector-cumulate, vector-partition, reverse-list->vector, and\nvector-append-subvectors each fill a scratch buffer before handing\nit to gc.allocVector, which copies it again.\n\nThe ~14 call sites gated behind \"only allocate past a 256-element\nstack buffer\" (vector-count, vector-any, vector-every, etc.) are\ndeliberately left alone: converting them is safe but their hot path\nnever touches the allocator, so there's no measurable benefit.\n\n* Document the allocator-fill finding and measured results\n\nExtend performance.md's \"when the profile bottoms out in memset\"\nsection with the second, distinct fill source this issue found\n(allocator convenience methods, not stack declarations) and why the\nexisting declaration-scope fix doesn't apply to it. Add a\nlessons-learned.md #11 entry with the measured benchmark deltas.",
          "timestamp": "2026-07-29T08:29:49+05:30",
          "tree_id": "10559fc909ec86234fb8833288f98d8fdb7a382b",
          "url": "https://github.com/kaappi/kaappi/commit/55e1bf32cd510d33f21db3c28dac84b5c3b25ca0"
        },
        "date": 1785296389432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358271,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.066969,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.58685,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.986204,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00469,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047266,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315617,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057174,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.657842,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.258564,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613749,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283593,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831632,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.61627,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043424,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "26334d245d9316529485ceed693cf50be343dfdd",
          "message": "Fix syntax-rules wholesale re-collection of sibling ellipsis variable, fixing #1721 (#1833)\n\nA template like `(list (list formal (list binding ...)) ...)` where\n`formal` and `binding` come from independent pattern groups\n`(_ (formal ...) (binding ...))` failed with EllipsisCountMismatch when\nthe groups had different lengths, and silently consumed `binding`\nper-iteration (instead of replicating it wholesale) when lengths matched.\n\nRoot cause: `templateReferencesVar` recurses into ALL sub-expressions\nincluding inner `(x ...)` sub-templates, so it wrongly marked inner-only\nbindings as driving the outer repeat count.\n\nFix: two-pass repeat-count determination. Pass 1 finds \"direct\" drivers\nvia `templateReferencesVarDirectly` (which skips sub-expressions consumed\nby inner ellipses) and deep (depth > 1) bindings. Pass 2 classifies\nremaining indirect-only bindings using `sharesInnerEllipsisWithDriver`:\nif a binding shares an inner `(elem ...)` sub-template with a Pass-1\ndriver, it belongs to the same pattern group and is consumed per-iteration\n(SRFI 149 excess-ellipsis replication); otherwise it's from an independent\ngroup and is passed through wholesale with its full list state intact.\n\nAlso tightens `ellipsisReferencesOuter` to use the same direct-reference\ncriterion, so a binding appearing only inside an inner ellipsis of a\nnested syntax-rules doesn't wrongly claim the ellipsis for the outer macro.\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T10:50:36+05:30",
          "tree_id": "a5dc876a82b46de62a3b54c4c53d26e0775ec50e",
          "url": "https://github.com/kaappi/kaappi/commit/26334d245d9316529485ceed693cf50be343dfdd"
        },
        "date": 1785304857018,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344853,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.543324,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612053,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.000421,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004796,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046801,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316304,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057665,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.665755,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23366,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.59588,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286026,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831379,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.623996,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1ef8268df43960aa38758a2746c032d93e77e1a0",
          "message": "Implement SRFI 150 (Hygienic ERR5RS Record Syntax), fixing #1810 (#1834)\n\nBuilds on SRFI 131's runtime substrate: a type name is bound directly to\nan ordinary SRFI 237 record-type-descriptor, with inheritance and\nfield/accessor/mutator resolution handled at run time by SRFI 237's own\nby-name introspection. The one piece SRFI 131 lacks -- hygienic\nfield/accessor-name matching for named constructor specs -- uses SRFI\n213 (identifier properties) instead of a query macro, so\ndefine-record-type itself is a SRFI 211 er-macro-transformer rather than\nan em-syntax-rules macro.\n\nTwo earlier designs (porting the reference's own SRFI 137 make-subtype\nclosures, then a from-scratch rewrite using a :secret descriptor macro\nover SRFI 237) both broke once more than one cross-expansion query\nrelationship existed side by side in the same program, isolated to\nem-syntax-rules engine bugs kaappi#1828 and kaappi#1829. This design\navoids that whole pattern by never threading anything across separate\ndefine-record-type expansions via a macro call.\n\n21 of 25 tests ported from the reference suite pass; the other 4 are\nmarked test-expect-fail/annotated, hitting a precise, minimal,\nrecord-free reproduction (kaappi#1832) of the already-documented\n\"top-level redefinition reaches the expansion\" hygiene limitation. A\nsecond new engine quirk (kaappi#1831) was found and worked around:\ncadar specifically fails when called from a helper function invoked\nduring an er-macro-transformer's expansion.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T10:50:53+05:30",
          "tree_id": "96c5f9a89acc11c428968eda72321dba0d5991f7",
          "url": "https://github.com/kaappi/kaappi/commit/1ef8268df43960aa38758a2746c032d93e77e1a0"
        },
        "date": 1785305368206,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.801842,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.202766,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.386289,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.039391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004223,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034061,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.212214,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040091,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.005934,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.840427,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.126569,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.221222,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.23975,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.696117,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.032836,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b83f4c249d757257f76758ff59c58b4a9026fa2d",
          "message": "Isolate -Dbundle test builds from the shared kaappi binary (#1826)\n\ncompile-import-error-703.sh and compile-preamble-gc-700.sh rebuilt\nzig-out/bin/kaappi in place to embed test bytecode, then rebuilt it a\nsecond time to restore the plain interpreter for later tests in the\nsame run-all.sh pass. run-all.sh and every other sequential test read\nthat same fixed path, so a test executed right after either of these\ncould race the restoring rebuild and observe a not-yet-settled binary.\n\nBoth invocations now install to a --prefix inside the test's own\ntmpdir instead, so the shared binary is never touched -- and the\nrestoring rebuild is no longer needed at all.\n\nFixes #1748\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T07:01:41Z",
          "tree_id": "a5a9f6a1cc86666147c66238c96fe18343c71d82",
          "url": "https://github.com/kaappi/kaappi/commit/b83f4c249d757257f76758ff59c58b4a9026fa2d"
        },
        "date": 1785310708270,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.417951,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.757462,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583902,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.9967,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004631,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046701,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.670374,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.237658,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594862,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277852,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812756,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65037,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043299,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "07adabaf2211c8c8b2388c6ba49dcc4bca09069e",
          "message": "Bound fuzz generator gates by instruction count on Debug builds (#1835) (#1836)\n\n`zig build test -Doptimize=Debug` is its own ubuntu-latest CI leg, and the\n`portable-subset generator: programs evaluate without error` gate fails on it.\nThe gate bounds each generated program by a 100 ms wall clock, which stops\ntracking work done as soon as the whole pipeline runs unoptimized.\n\nMeasured over the gate's own 60 fixed seeds under Debug: the in-`vm.eval`\nwindow is 35 ms min / 91 ms median / 435 ms max against that 100 ms budget --\nthe median *correct* program already sits at the threshold. 9 of 60 seeds\nmissed, every one as `.resource_limit`, none as a compile or runtime error.\nTwo structural details make the miss set jitter rather than a real\nslow-program signal: the deadline is only checked inside `runUntil`, so the\nfixed leading `(import (scheme base) (scheme char) (scheme lazy)\n(scheme write))` -- ~26 ms, a quarter of the budget -- spends it without ever\nbeing able to trip it, and read/expand/lower/emit are unchecked for the same\nreason. Consecutive runs of the same fixed seeds disagree about which seeds\nmiss, which is what made this look nondeterministic.\n\nThis is the same wall-clock-vs-slow-execution class already fixed for\ngc-stress (#1447/#1449) and for emulated cross-compiled targets (#1573), where\nthe gates bound by instruction count instead -- speed-independent, identical\nno matter how fast each instruction runs. Debug was never added to that list.\n\nFold `builtin.mode == .Debug` into `speed_independent`, so Debug takes the\nexisting 2M-instruction bound and 120 s wall-clock backstop unchanged. The\nchange is confined to `src/tests_fuzz.zig`; the shipped binary is unaffected.\n\nThe existing regression guard could not have caught this: its two branches are\nself-consistent with whatever `speed_independent` evaluates to, so a mode\nmissing from the definition just takes the other branch and passes. Add an\nexplicit `if (debug_build) try expect(speed_independent)` ahead of them.\nMutation-tested: dropping the `or debug_build` term makes the guard fail on\nthat exact assertion under Debug.\n\nThe issue also reported a second failure mode -- a native stack overflow with\na repeating `eval -> compile -> lower -> eval` cycle and \"445+ additional stack\nframes skipped\". That is not a stack overflow and not a second bug. The message\nis emitted only by `writeErrorReturnTrace` (std/debug.zig, `skipped =\net.index - len`), so it is an accumulated *error return trace*, not a call\nstack; the \"cycle\" is ~50 repetitions of one 9-frame CompileError propagation\npath. The Debug run that produced it ended in an ordinary test failure\n(1377 pass, 4 skip, 1 fail), with no panic. Its `--seed` dependence was also\nillusory: in non-fuzz mode Zig replays only the fixed corpus, and these gates\nuse hardcoded seeds 0..59, so the 60 programs are byte-identical every run.\n\nVerified: full unit suite green under both `-Doptimize=Debug` and ReleaseSafe;\n`-Dtest-filter=generator` under Debug goes from 1 fail to clean.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T08:13:39Z",
          "tree_id": "be4a83135112401f4c161ba7fccbe6a72338b758",
          "url": "https://github.com/kaappi/kaappi/commit/07adabaf2211c8c8b2388c6ba49dcc4bca09069e"
        },
        "date": 1785314913189,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.086798,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.097804,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.413152,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.195082,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004327,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03481,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229714,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.04209,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.092697,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.932788,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.201289,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234582,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.317626,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.739714,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034441,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6e9043b3f3e2faf8f03b8a0e14507943faaf4374",
          "message": "Hygiene-rename free-global macro references to avoid arg collisions (#1839)\n\nexpandAndCompileMacroUse implemented R7RS 4.3.1 referential\ntransparency for a template's free reference to a global that already\nexisted at the macro's definition time by temporarily marking that\nglobal VOID, signaling renameForHygiene to leave the reference\nunrenamed so an injected register alias could pierce use-site\nshadowing under that bare name.\n\nA bare, unrenamed reference is indistinguishable from any other\nidentifier of the same spelling introduced elsewhere in the same\nexpansion -- including a pattern-variable argument the caller supplied\nwith that exact spelling. `(def a)`, where `def`'s own template\nfree-referenced a pre-existing global `a` while also taking `a` as an\nargument, collapsed both to the same bare symbol: `(let ((a 5)) (def2\na))` returned `(999 999)` instead of `(999 5)`, and a set!-based\nvariant could overwrite an unrelated use-site local instead of leaving\nit untouched.\n\nThe reference is now hygiene-renamed like any other\ntemplate-introduced identifier (mirroring what a set!-target prescan\nalready did, and how injectHygienicCapturedLocals already handles the\nanalogous captured-local case from #1288), and its\nreferential-transparency alias is injected under that renamed name --\nfound by walking the expansion, in injectHygienicGlobalAliases --\ninstead of the bare one. compileSet's write-through (both the legacy\nand IR compile paths) now targets the real global name via a new\nLocal.alias_global_name field rather than assuming the alias local's\nown name matches it.\n\nFixes #1832\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T15:02:17+05:30",
          "tree_id": "eef0e2eb41b2a93876a602c273fad9e0674b6ee6",
          "url": "https://github.com/kaappi/kaappi/commit/6e9043b3f3e2faf8f03b8a0e14507943faaf4374"
        },
        "date": 1785319783802,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.839922,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.03053,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.548895,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.743858,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28397,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053472,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.766567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.11009,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.485242,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.263151,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.665809,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.921716,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04088,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5f74d6663b888e7dff3f672873d87050d4027c85",
          "message": "Comptime-gate lever-D bytevector checks in gc_collect.zig, fixing #1794 (#1838)\n\n`Bytevector.shared` is only ever set by `allocBytevectorShared`, called\nsolely from gc_deep_copy.zig's `if (comptime instrument.enabled)` block\n(KEP-0002 Phase 7 lever D, kaappi#1472). In a shipped build the field is\nprovably always null, but `freeObject` and `objectSize` in gc_collect.zig\nstill branched on it at runtime. Wrap both in the same `comptime\ninstrument.enabled` gate gc_deep_copy.zig already uses, so a shipped\nbinary never loads the field and a reader can tell from the code that\nthe branch is dead there.\n\nBehavior is unchanged in both build modes -- verified via `zig build\ntest` under the default and -Dchannel-instrument=true configs (including\ntests_shared_channel.zig's lever-D test, which exercises both changed\nsites), plus the full `tests/scheme/run-all.sh` suite (2009 pass, 0\nfail). This is a comptime dead-code-elimination clarity fix with no\nbehavioral change, so no new regression test is added.",
          "timestamp": "2026-07-29T15:02:39+05:30",
          "tree_id": "05f766564c8d5773e840fbf30f6d3f034972ff9b",
          "url": "https://github.com/kaappi/kaappi/commit/5f74d6663b888e7dff3f672873d87050d4027c85"
        },
        "date": 1785320365649,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.037525,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.282572,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57214,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.841028,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004951,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045263,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302667,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054359,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.338138,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.181388,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.525819,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.310515,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.729496,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.769617,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047117,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "70450499b7bc80cee6656bcea021f8a265fe1120",
          "message": "Add Markdown linting to CI, fixing #1837 (#1840)\n\n* Add Markdown linting to CI\n\nThe repo had 82 Markdown files and no linter, while .zig was enforced three\nways. The gap was not theoretical: CodeRabbit -- not CI -- caught an MD018\nviolation in docs/dev/fuzzing.md (#1836), where prose wrapping left an issue\nreference at the start of a line, which Markdown reads as a malformed heading.\nThat failure mode is silent -- the doc renders wrong on GitHub and nothing\nerrors anywhere.\n\nMeasuring the fallout first changed the approach. The default rules give 2792\nviolations, but MD013 (line-length, 1032) and MD060 (table pipe padding, 997)\nalone are 73% of that noise. With those and nine other cosmetic rules off, 507\nremain -- few enough to clear entirely rather than start from a deliberately\nnarrow rule set and widen it over time. Every structural rule is therefore on,\nand the repo is left at zero findings.\n\nTwo of those rules must never be autofixed blindly, which is why the five\naffected sites were corrected by hand before running --fix:\n\n  - MD018 \"fixes\" a line-initial issue reference by inserting a space,\n    promoting prose to a real top-level heading -- making the very bug that\n    motivated this check worse. Doing so newly surfaced three MD025, one\n    MD026, and one MD001 as the phantom headings took effect.\n  - MD038 strips the space from the space-character literal in\n    docs/dev/fmt.md, corrupting the Scheme literal that paragraph exists to\n    document.\n\nBoth hazards are recorded in CONTRIBUTING.md so a later --fix cannot quietly\nreintroduce them.\n\nGlobs, ignores, and the rule set live together in .markdownlint-cli2.jsonc so\na bare `npx markdownlint-cli2` lints exactly what CI lints. AGENTS.md is\nignored because it is a symlink to CLAUDE.md and would double-report every\nfinding.\n\nFixes #1837\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix the MD018 violation the new check caught on main\n\nThe first CI run of the markdownlint step failed -- on a real violation,\nin the exact file and of the exact class that motivated this work.\n\ndocs/dev/fuzzing.md carried `#1573),` at the start of a line, which\nMarkdown reads as a malformed ATX heading. CodeRabbit flagged it during\nreview of #1836 and issue #1837 was filed about it, but the line merged\nto main unfixed. CI lints the pull-request merge commit, so the check\nsaw it even though this branch's own base predates that merge.\n\nFixed by rewrapping, never by MD018's autofix, which would have inserted\na space and promoted the prose to a real heading. The first rewrap\nattempt merely moved the problem to the following line (`#1835).`),\nwhich the check also caught -- the wrap point has to be chosen so that no\nline begins with the reference. The paragraph's word sequence is\nbyte-identical to main's.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T15:03:03+05:30",
          "tree_id": "ea76b813c4281128cc8379ea27f23f5fb25dac6c",
          "url": "https://github.com/kaappi/kaappi/commit/70450499b7bc80cee6656bcea021f8a265fe1120"
        },
        "date": 1785320959688,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.006945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.368754,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573906,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.843908,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004933,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045208,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302195,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054352,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.367794,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.18058,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519851,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302982,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.723025,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699176,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045383,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9b1c479c0a8070e40d326394e707308e48da1762",
          "message": "Add regression tests for #1716's recursive generated-macro quote (#1841)\n\n#1716 reported that a macro-generating macro whose generated helper is\nself-recursive and quotes one of its own pattern variables substituted\nthe literal pattern-variable name instead of the captured identifier:\n`(collect a b c)` yielded `(nm nm nm)`.\n\nBisecting the repro against builds of 55e5bc6 (the commit that added\nSRFI 209, where the bug was found) and 76d6012 shows the defect was\nalready fixed by #1773 -- renameForHygiene used to skip the hygienic\nrename for any quoted identifier, splitting a nested syntax-rules\ntemplate's quoted occurrence of a pattern variable from the rename its\nown pattern side had already claimed. #1773 landed its own test for the\nnon-recursive shape only, so the recursive shape #1716 actually\ndescribed was left unpinned.\n\nAdd that coverage: three unit tests in tests_macros_nested_sr.zig\n(self-recursive, mutually recursive, and a quoted pattern variable\ninside a larger quoted list/vector datum) and an end-to-end Scheme\nsuite. Verified as real regression tests -- 11 of the Scheme suite's 13\nassertions fail on a pre-#1773 build and all pass now.\n\nAlso refresh the SRFI 209 comment that documented the workaround: the\nconstructor still routes through `type-name` rather than quoting `nm`\ndirectly, but now because `type-name`'s literals list rejects a name\noutside the enum type at expansion time instead of failing later inside\n`enum-set-adjoin` -- not because the expander can't handle the quote.\n\n\nClaude-Session: https://claude.ai/code/session_01KRP1wxfAwqVubfSW5TMK7Y\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:06:42+05:30",
          "tree_id": "8c1e2ea0c6c20476facd9c07063f78c8c0e4506f",
          "url": "https://github.com/kaappi/kaappi/commit/9b1c479c0a8070e40d326394e707308e48da1762"
        },
        "date": 1785327979871,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.365796,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.795365,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.577292,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.973045,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004732,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047016,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315232,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057001,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.615204,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.238539,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617288,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280132,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799592,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.613621,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044097,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "425c5d8f348b203cf2458401e22b31f68a7466a1",
          "message": "Cover macro-generated top-level define read-back, fixing #1829 (#1842)\n\nAn em-syntax-rules macro whose expansion defined a fresh top-level\nbinding and read it back in the same generated `begin` got a previous\nexpansion's same-spelled binding instead of its own. The issue was filed\nbefore #1839 landed and is already fixed by it -- A/B confirmed against\n07adabaf (fails) and 70450499 (passes) -- but nothing in the suite\ncovered the shape, so a future change to the free-global alias mechanism\ncould silently reintroduce it.\n\nThe issue's own hypothesis (a global inline cache keyed more coarsely\nthan binding identity) was not the cause. Because the CK machine builds\nits output as plain data, a macro-generated top-level define lands under\nits BARE name -- unlike a syntax-rules template, whose introduced define\nis hygienically renamed. That makes the bare name a real global, so the\nnext expansion's own reference to it is a free reference to an\nalready-bound non-procedure global, which the pre-#1839 code left\nunrenamed so an injected alias could pierce use-site shadowing (R7RS\n4.3.1). The bare reference was then indistinguishable from the parent's\nown symbol threaded back in by the `=>` query: the collision of #1832,\nreached through a generated define rather than a pattern variable.\n\nThe test asserts both the reported four-use sequence and a tighter case\nfound while isolating it -- pre-binding the storage name makes the\npre-fix build fail on the very FIRST parent-having use rather than the\nfourth. Read-backs are recorded through a procedure, which the alias\nmechanism excludes, so the recorder cannot perturb what it measures.\nBoth assertions were verified to fail pre-fix and pass post-fix.\n\nCLAUDE.md and lib/srfi/150.sld both described #1829 as a live bug;\nthey now record it as fixed with the real mechanism. #1828, re-checked\nand still reproducing, is untouched by that fix and on its own still\nrules out the query-macro approach SRFI 150 rejected, so no design note\nbelow it changes.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:29:30+05:30",
          "tree_id": "fb8c8b038244ccdcb15a3f20b1e533267105aaef",
          "url": "https://github.com/kaappi/kaappi/commit/425c5d8f348b203cf2458401e22b31f68a7466a1"
        },
        "date": 1785328451325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.004731,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.456413,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566613,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834439,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004893,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302746,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054359,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.371465,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.182313,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51821,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.717729,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.739912,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044865,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a251304138e761f239a50b1a28eb78bc1253d28e",
          "message": "Resolve library globals identically in all three global-ref opcodes (#1843)\n\nA library body's reference to a global that lives in vm.globals but not\nin its own lib_env resolved in tail position only. The compiler picks a\nglobal-reference opcode purely by syntactic position -- get_global plus\na plain tail_call for a tail call's operator, the call_global\nsuperinstruction for every other call -- but only get_global carried the\nvm.globals fallback library code has needed since 455f5cc2. So a library\nimporting just (scheme base) could call `(cadar x)` as its body's last\nform and got \"undefined variable 'cadar'\" for the identical call one\nsyntactic position over, which surfaced as a bare \"invalid syntax\" when\nthe caller ran at macro-expansion time.\n\nRoute get_global, call_global, and tail_call_global through one\nlookupGlobalLocked helper that takes the Function rather than a\npre-picked env, so all three see the same chain: the function's own\nenvironment, then vm.globals when it runs in a library (or eval)\nenvironment and is not restricted, then both again with any hygienic\nrename prefix stripped. The restricted_globals gate keeps a restricted\n(environment ...) as tight for a non-tail call as #1253 already made it\nfor a tail call.\n\nThis is also the \"unrooted-out compiler quirk\" documented for the SRFI\n237 primitives: a %-prefixed internal primitive is a vm.globals-only\nname, so it looked ambient in some positions and not others. Restore the\nidiomatic `cadar` in lib/srfi/150.sld's field-alist-ref and correct both\nCLAUDE.md notes -- `cadar` was never special, it was just the one\n(scheme cxr) name that file calls from a library-body helper.\n\nFixes #1831\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:30:55+05:30",
          "tree_id": "49f81e6a27feda3e726b94051192461098ae1e07",
          "url": "https://github.com/kaappi/kaappi/commit/a251304138e761f239a50b1a28eb78bc1253d28e"
        },
        "date": 1785329278888,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.207275,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.784655,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.444489,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.290458,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004574,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035444,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.234637,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.046186,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.202524,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.927404,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.178374,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.25413,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.37079,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.771885,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035485,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4f0e04165903f96704c1ea8a9ede4085d4dfb2a3",
          "message": "Use list? instead of pair? for user-supplementary-gids audit test (#1845)\n\nSRFI 170 only promises user-supplementary-gids returns a list, not a\nnon-empty one. pair? fails for any process with no supplementary\ngroups, such as root in a minimal container image. The two other\ntests of this primitive (src/tests_filesystem.zig, coverage/\nfilesystem-coverage.scm) already use list?; this brings the audit\ntest in line with them.\n\nFixes #1844\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T12:52:04Z",
          "tree_id": "44ceb0e5a1e83dd91dd133b93297aa0b7c810e5a",
          "url": "https://github.com/kaappi/kaappi/commit/4f0e04165903f96704c1ea8a9ede4085d4dfb2a3"
        },
        "date": 1785332436286,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.262318,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.344864,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.585604,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.017051,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045906,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313121,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057236,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.731045,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224679,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.575115,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282595,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.778713,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714679,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046558,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f5fefdd98f6ab54f4f6eacff3e142aa175e6639b",
          "message": "Surface procedural macro transformer errors instead of bare \"invalid syntax\" (#1847)\n\nA Scheme-level condition raised inside a SRFI 211 er-macro-transformer/\nlisp-transformer was computed, stored on the VM, and discarded before the\ncompiler's TransformerFailed collapsed to a generic InvalidSyntax -- #1831\nwas a one-line resolution bug whose real message was \"undefined variable\n'cadar'\", none of which reached the user, so it was chased for days as a\ncadar-specific primitives bug instead.\n\nglobals.error_detail_for_macro exposes the VM's last error detail to the\ncompiler (which cannot import vm.zig), and compiler_macro.zig's two\nTransformerFailed arms copy it into the same syntax_error_detail channel\nsyntax-error already reports through. vm.callProcForMacro also now calls\nnoteUncaughtException on failure: callReentrant (used to invoke the\ntransformer's own closure) preserves last_error_detail across its cleanup\nbut never populates it from current_exception the way execute()'s\ntop-level boundary does, so a plain (error \"msg\" ...) raised with no\nactive handler left last_error_detail empty -- confirmed with a throwaway\ndebug print before writing the real fix. A primitive's own type error\n(e.g. (car 7)) already set the detail directly and needed no VM change.\n\nFixes #1846.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T19:34:59+05:30",
          "tree_id": "3e25d8b6cac716966277cac77537ad3788f4aa8f",
          "url": "https://github.com/kaappi/kaappi/commit/f5fefdd98f6ab54f4f6eacff3e142aa175e6639b"
        },
        "date": 1785336095846,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.052888,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.049565,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572425,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.465807,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004673,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.049463,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.368885,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650948,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.422637,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619859,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28025,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.955041,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.556314,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046612,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "85eb70ad47e31c833af1c2bccb200ccfd2fa2f3b",
          "message": "Close #1828 as not-a-bug: unquoted em-syntax-rules template, not chaining (#1849)\n\nThe reported \"variable bound by one => step can't be used as the operator\nof a later chained step\" symptom is fully explained by the repro's own\nfinal template being unquoted while calling an ordinary procedure\n(display) -- SRFI 148's spec documents that as an error case (\"It is an\nerror if the expanded output is not an eager macro use or a self-quoting\nsyntax element\"). The issue's exact repro, with only the final template\nquoted, already works correctly. Adds a regression test locking in the\ncorrect (already-working) operator-position chaining at 2 and 3 levels,\nand corrects the three places that cited #1828 as a confirmed, still-open\nengine bug.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:15:08Z",
          "tree_id": "da74a46e2f02dc2360d76d6397309619c17bf50a",
          "url": "https://github.com/kaappi/kaappi/commit/85eb70ad47e31c833af1c2bccb200ccfd2fa2f3b"
        },
        "date": 1785347566928,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.046965,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.626059,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566426,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.835356,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004886,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044353,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297311,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054829,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.336662,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.173455,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.515401,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304926,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.701495,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.771019,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0822034d6d86cea9ac665ef3eb99a0f8c98e350a",
          "message": "Reclassify digit-led glued identifiers from KP1002 to KP1004 (#1848)\n\n* Reclassify digit-led glued identifiers from KP1002 to KP1004\n\n`3-state`, `5foo`, `1.2.3`, and similar tokens are correctly rejected --\nR7RS identifiers can never begin with a digit -- but the reader had\nalready committed to parsing a number on the leading digit, so the\ngeneric KP1002 (\"unexpected character\", whose explanation talks about\nstray '#'-syntax) named the wrong category, gave no hint, and pointed\nthe caret one column past the token's actual start.\n\nSuch a token now reports KP1004 (\"invalid number literal\"), the\naccurate code since the reader already committed to a number, with the\ncaret at the token's start and a message that echoes the offending\ntoken and states the rule. Surfaced consistently across the CLI's text\noutput, `kaappi check`, `kaappi compile`, and `--diagnostics=json` via a\nnew reader detail-message channel mirroring the compiler's existing one.\n\nFixes #1723.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on the digit-led-identifier fix\n\n- readNumber's wrapper reclassified to KP1004 whenever any non-delimiter\n  followed a number, not just an identifier-continuation character. A\n  stray backtick or comma (e.g. `3\\``) is neither a delimiter nor an\n  R7RS <subsequent> char, so it wrongly took the new path and reported\n  \"invalid number literal '3': ... cannot begin with a digit\" -- both\n  mislabeling the valid number '3' and dropping the actual offending\n  character. Now only reclassifies when consumeGluedIdentifierChars\n  actually consumes at least one character; otherwise it falls through\n  to the original, accurate UnexpectedChar (KP1002).\n\n- setReadErrorDetail's bufPrint-overflow fallback claimed the full\n  256-byte buffer as valid content without knowing how much a failed\n  write actually populated. Rebuilt on Io.Writer + buffered().len --\n  the same pattern compiler.formatSyntaxError already uses -- so a\n  pathologically long malformed token (the format string embeds it\n  twice) truncates to a clean prefix instead of risking a stale tail.\n\n- Strengthened the \"valid numbers are unaffected\" test to assert each\n  case's actual type/value (fixnum/complex/flonum/rational) rather than\n  just that reading succeeded, and added regression tests for both\n  fixes above plus the equivalent CLI-level cases.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:26:19Z",
          "tree_id": "36ee992365ae3d5ee4934aa12b56146634115bb2",
          "url": "https://github.com/kaappi/kaappi/commit/0822034d6d86cea9ac665ef3eb99a0f8c98e350a"
        },
        "date": 1785348131357,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.08385,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.791491,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.436813,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.17329,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003767,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227202,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041663,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.772529,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.888564,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.170878,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238203,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314515,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.40522,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035602,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "784bcc9954f55443add315f8c19eafb096d9bc88",
          "message": "Add /create-announcement skill for release announcements (#1851)\n\n* Add /create-announcement skill for release announcements\n\nPosting a release to the org forum was an undocumented manual task, and\nthe one non-obvious fact it depends on was written down nowhere: org-level\ndiscussions at github.com/orgs/kaappi are backed by the kaappi/kaappi\nrepository, not by kaappi/.github, which has discussions disabled entirely.\nA skill that guessed the obvious repo would fail on every run, so the repo\nand category ids are pinned in the file for the GraphQL fallback that\ncovers `gh discussion` still being a preview command.\n\nThe skill carries the editorial half as well as the mechanics. Release\nnotes are exhaustive by design; an announcement is not a second copy of\nthem, so the file specifies how to pick 3-6 highlights (what a user can now\ndo, not what changed), a body template, and a rule that every claim trace\nback to the notes. Posting stops for explicit approval first: it publishes\npublic content in a maintainer-restricted category and notifies every org\nwatcher.\n\nRunning it against v0.21.0 surfaced a defect in the skill itself that also\naffects skill authoring generally, hence the harness-doc section. A dollar\nsign followed by a digit inside a SKILL.md is rewritten by slash-command\nargument expansion before the body is ever read, so a snippet in the file\nis not necessarily the snippet that runs. The numbering is zero-indexed --\nthe zeroth token takes the *first* argument -- an absent argument leaves the\ntoken untouched rather than emptying it, and code fences do not protect\nanything. All of that is measured from probe invocations at 0, 2, and 3\narguments rather than inferred; an earlier inference here was wrong in a way\nthat would have caused three unnecessary edits.\n\nThe awk field variables in the DigitalOcean skills are therefore left alone:\nthey read the third argument, those skills take none, and they were never\nbroken. Their cost notes were the real exposure, since a dollar sign followed\nby zero claims the first argument and a single stray argument is enough to\ngarble the figure.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: harden duplicate detection and fix two contradictions\n\nDuplicate detection listed the 30 newest announcements, which is exactly\nbackwards for the case that needs it most: announcing an older release, where\na duplicate is by definition not among the newest. Searches by tag instead --\nverified it returns the v0.21.0 announcement and nothing for an unannounced\ntag.\n\nThe GraphQL fallback fired on any non-zero exit from `gh discussion create`.\nThat mutation is a non-idempotent write, and a lost response -- posted server\nside, reply never arrived -- is indistinguishable from an outright failure at\nthe call site, so the fallback could publish a second announcement and notify\nevery watcher twice. It now re-runs the tag search first and only proceeds on\na zero count.\n\nTwo contradictions were self-inflicted. The troubleshooting row still claimed\nthe `@` and `*` forms get substituted, contradicting the measured table added\nin the same branch, which records that they never do. And the harness guide\nsaid \"seven steps\" for a skill that numbers eight, 0 through 7.\n\nThe link checker's character class excluded whitespace but not `>`, so an\nangle-bracket autolink contributed a URL with the delimiter attached and\nreported a spurious failure -- which blocks approval on a phantom defect,\nthe one failure mode a pre-flight check must not have. Also narrowed the\nmaintainer-restriction note: `kaappi/kaappi` is public, so a read-only token\ngets through both read steps and fails only on the write.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T23:33:24+05:30",
          "tree_id": "7558634fc17729f8435095fec0415861482ed320",
          "url": "https://github.com/kaappi/kaappi/commit/784bcc9954f55443add315f8c19eafb096d9bc88"
        },
        "date": 1785351459760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301584,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.509072,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575373,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.945859,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004666,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046999,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312916,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057159,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650102,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216049,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276192,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794445,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.60208,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042692,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "ca18ae69c906ea598462a9d4a92438048f1ee880",
          "message": "Release v0.22.0\n\n93 new SRFIs (85 -> 178), closing the #1694 numeric-vector/array family,\n#1695 records, #1699 macros and syntax, plus #1702/#1703/#1810. The\nengine work behind them: procedural macro transformers (SRFI 211/213),\nnative apply lowering, and the types.zig split into 11 domain files.\n\nAlso refreshes counts that had drifted: built-in procedures 641 -> 690,\nprimitives files 26 -> 31, SRFI count 177/174 -> 178, and the R7RS suite\n1,391 -> 1,395 (what run-all.sh actually reports). SRFI 150 was missing\nfrom the CONFORMANCE table entirely; the table now cross-checks exactly\nagainst `kaappi features`.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T00:06:54+05:30",
          "tree_id": "d57dfad572decd1c4e313321ce9a5aefa255a8f8",
          "url": "https://github.com/kaappi/kaappi/commit/ca18ae69c906ea598462a9d4a92438048f1ee880"
        },
        "date": 1785352837302,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.948831,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.041143,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560853,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.809119,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00488,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044525,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293782,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054496,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.343196,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.505738,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305107,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.696183,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.803528,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045322,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "65743ab14c4cf2aec12de89182ebb9b45d38ea61",
          "message": "Split six oversized source files along their natural seams (#1853)\n\n* Split six oversized source files along their natural seams\n\nmemory.zig (2112 lines), expander.zig (1982), llvm_emit.zig (1710),\nvm_library.zig (1573), compiler_macro.zig (1530), and gc_collect.zig\n(1512) had all grown past the 1500-line file size policy through\ntangled coupling rather than breadth, so each is split at the seam\nwhere two domains shared one file:\n\n- memory.zig keeps the GC machinery (lifecycle, rooting, write\n  barrier, quarantine); the 61 allocXxx constructors move to\n  gc_alloc.zig, aliased back into GC so gc.allocXxx(...) call sites\n  are untouched (the existing gc_collect/gc_deep_copy precedent).\n- expander.zig keeps macro-use entry points, pattern matching, and the\n  hygiene-strip walks; template instantiation + renameForHygiene move\n  to expander_instantiate.zig, sharing the threadlocal expansion\n  context through qualified references.\n- llvm_emit.zig keeps the emitter core; the special-form and\n  eval-fallback emitters join the existing cond/case/do satellite\n  llvm_emit_forms.zig, aliased back into LLVMEmitter.\n- vm_library.zig keeps library definition/loading/SRFI 261/features;\n  the import-set algebra (only/except/prefix/rename) moves to\n  vm_imports.zig and is re-exported under its old names.\n- compiler_macro.zig keeps the macro-use path; the macro-defining\n  forms, SRFI 147 transformer-spec resolution, and syntax-rules\n  parsing move to compiler_define_syntax.zig, re-exported through the\n  same names so compiler_forms dispatch is unchanged.\n- gc_collect.zig keeps orchestration/marking/weak refs; the sweep\n  phase with the objectSize and freeObject per-tag switches moves to\n  gc_sweep.zig.\n\nPure code motion — no behavior change; same-name aliases keep every\ninternal and external call site compiling as-is. CLAUDE.md tables, the\nheap-type checklist, docs/dev (architecture, adding-features, harness),\nand the gc-safety rule globs (now src/gc_*.zig and src/expander*.zig)\nupdated to match. Remaining >1500-line files are the policy-exempt\nkinds: primitives_* and tests_* breadth, and generated unicode_tables.\n\nVerified: zig build test, full tests/scheme/run-all.sh (2013 pass,\n0 fail), and x86_64-linux / aarch64-windows / wasm cross-compiles.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1853 review findings\n\nThe one reachable bug: compileLetSyntax registered its root-stack\ncleanup defer only after the binding loop, so a mid-loop InvalidSyntax\n(malformed later binding) or a failing resolveTransformerSpec returned\nwith earlier iterations' roots still pushed — permanently, since\nnothing resets the root stack on compile errors. The defer now\nregisters before the loop (still after tx_vals's deinit defer, so the\npops keep running first). Regression test fails without the fix.\n\nAlso from review: substitutePatternVarsOnly was caller-less (already\ndead before the split) and is removed, with the renameForHygiene doc\ncomment it had swallowed moved to the function it describes; gc_collect\ndrops the imports and type aliases only the moved sweep code used;\nstale gc_collect attributions in gc_alloc.zig/memory.zig comments now\nsay gc_sweep; the compiler table heading says 11 files (it had been\noff by one since before this PR); adding-features.md gains the\ntypes.zig typeName step.\n\nThe remaining review findings are deliberately not fixed here: the\nthree expander_instantiate push/pop sites are OutOfMemory-unwind-only\n(every user-reachable ExpandError path unwinds balanced) and match the\ndocumented canonical pattern used codebase-wide, and the native-backend\ninternal-define rooting question predates the split byte-for-byte —\nboth filed as issues instead.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T10:00:34+05:30",
          "tree_id": "d03d5c0fbf275c546dc0c8a575f244c9413a3bf4",
          "url": "https://github.com/kaappi/kaappi/commit/65743ab14c4cf2aec12de89182ebb9b45d38ea61"
        },
        "date": 1785388109052,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.255285,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.606989,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561826,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.967353,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004648,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04594,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309985,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056846,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.619017,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.217186,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58321,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.776658,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.646559,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04271,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1ecf1c4cd41701054b8c7e2766bb1c5b30062a1e",
          "message": "Root internal-define slots in native let bodies (#1854) (#1857)\n\n* Root internal-define slots in native let bodies (#1854)\n\nThe LLVM backend gave an internal `define` in a `let` body its own alloca\nbut never pushed it on the GC shadow stack, so the binding held the only\nreference to a freshly allocated value across every later allocation in\nthat body. A collection freed it and the memory was recycled into\nwhatever the body allocated next — a wrong answer in a compiled binary,\nwith no crash and no divergence in the interpreter:\n\n  (let ((a 1))\n    (define xs (list 11 22 33))\n    (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))\n    (car xs))            ; => 198492, not 11\n\nWhen the define held a procedure it was worse: calling the collected\nclosure died with \"not a procedure\".\n\nMove ownership of these slots to emitLet, which already owns the scope's\nroot accounting. Before emitting the body it walks the leading run of\n`(define <symbol> <expr>)` forms — R7RS's position for internal\ndefinitions — and for each mints an alloca, stores VOID, pushes it, and\ncounts it into the same binding_root_count the let's own bindings use.\nemitDefine's internal path now only evaluates the initializer and stores\ninto that slot, recognizing it through the new\nLLVMEmitter.scope_define_names.\n\nemitLet has to be the owner because the scope pops a fixed n at exit, so\nevery push it counts must execute exactly once. Pushes at the head of the\nbody dominate it; one emitted at a define nested inside an `if` would run\non one path only. Those are exactly the defines scope_define_names omits,\nand emitDefine answers UnsupportedNodeType for them so the enclosing let\nabandons and the interpreter — which binds a non-head define correctly —\ntakes the whole form.\n\nPre-creating every slot before any initializer runs is also letrec*\nsemantics, which is what a body of internal definitions means: a forward\nor self reference now reads VOID (bound but not yet assigned) instead of\nthe uninitialized alloca it read before.\n\nNo musttail interaction (#1499): mustTailSafe already requires\nself.locals == null, never true inside a let body.\n\nThe new compile test diffs native output against the interpreter for\nhead defines under GC pressure (single, multiple, nested lets, let*,\n`(let () ...)`, a procedure-valued define, redefinition, letrec*\nordering), pins the fallback shapes (a define inside `if`, after an\nexpression, begin-spliced), keeps #819's shadowing guard, and asserts\nthe emitted push/pop counts in @main balance. Nine of its cases fail\nagainst the pre-fix binary; the balance assertion catches a dropped\nroot count.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review on the #1854 regression test\n\nTwo real problems in the new test driver, both flagged in review of #1857:\n\n- The runtime-archive setup hard-coded `zig-out/lib/libkaappi_rt.a` and\n  called `zig build lib` directly, copied from the older compile tests.\n  `shell-common.sh` has `ensure_runtime_lib` for exactly this: it knows\n  the archive's per-platform name (`rt_lib_name`) and accepts a prebuilt\n  one on a box with no Zig toolchain, so a machine running\n  cross-compiled binaries still exercises the compile+link path instead\n  of dying at `zig: not found`.\n\n- `--emit-llvm` was invoked with `|| true`, so a failed emission (or a\n  missing `.ll`) parsed as zero `kaappi_eval_cached` calls — which is\n  what a `native` case asserts. The one check meant to keep a silent\n  interpreter fallback from making a case pass vacuously could itself\n  pass vacuously. It now fails loudly; mutation-tested by replacing the\n  invocation with `false`.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:09:40+05:30",
          "tree_id": "4f28fdf7862de077935dcbf6570130467890429c",
          "url": "https://github.com/kaappi/kaappi/commit/1ecf1c4cd41701054b8c7e2766bb1c5b30062a1e"
        },
        "date": 1785403178859,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.274031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.563857,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.849652,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045187,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.303359,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.504615,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156775,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.59125,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.273202,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.764437,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.511801,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044747,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ac7369522e55d0bf4d5269079d1ab488548069d",
          "message": "Stop (scheme base) from exporting %-prefixed internals (#1859)\n\n* Stop (scheme base) from exporting %-prefixed internals\n\n`(scheme base)` exported 22 `%`-prefixed internal primitives. Since v0.22.0\nalso began enforcing R7RS 5.2 (#1726), any user library that defined one of\nthose names and imported `(scheme base)` failed to load outright — the\ndocumented C-extension walkthrough, whose example exported `%length`, was\none such casualty. `%` is this codebase's own private-helper marker, so\nuser code has good reason to treat that namespace as its own.\n\nThe 22 names move off the `scheme.base` tag, and a comptime check in\nprimitives.zig now rejects any `%` name tagged with a `scheme.*` library.\nWhere they went depends on who names them:\n\n  - Only Zig-generated code names them (`%make-promise-lazy`,\n    `%parameter-set!`, `%parameter-convert`, the record substrate and its\n    `/inherit` variants): `.internal` — registered in vm.globals, exported\n    by nothing.\n  - A portable `.sld` names them in its own Scheme source (SRFI 27's\n    random-source accessors, SRFI 74's endianness probe, SRFI 271's random\n    ports, the record substrate SRFI 57/131/136/150/237 build on): also\n    `.internal`, plus a new `(kaappi primitives)` library those `.sld`s\n    import, so each declares the dependency it actually has.\n\nUnexporting them alone would have converted a loud error into a silent\nwrong answer: a library defining its own `%record-ref` would load, and its\n`define-record-type` accessors would then call it. Compiler-synthesized\nreferences therefore go through `Compiler.trueBuiltinRefOrSymbol` /\n`globals_mod.baseBindingSymbol`, resolving against a pristine startup\nsnapshot (`LibraryRegistry.internal_bindings`) rather than vm.globals —\nthe mechanism #1715 already used for let-values.\n\n`%length` is deleted rather than relocated: case-lambda's arity dispatch\nnow references `length`'s pristine `(scheme base)` binding directly, which\nis what the alias existed to approximate (#1714) and is strictly stronger,\nsince a top-level `(define (%length x) ...)` could overwrite the alias but\ncannot touch the export table.\n\nTwo adjacent fixes fall out:\n\n  - `kaappi check` no longer reports KP4001 on base-binding-prefixed\n    references. This was already wrong for let-values' synthesized\n    `call-with-values`; case-lambda, define-record-type, parameterize and\n    delay would have made it common.\n  - The globals drift guard now tests the invariant it meant to\n    (`vm_bootstrap.internal_helpers` are purged) instead of assuming every\n    `.internal` spec is purged, which only held while the two sets\n    coincided.\n\nFull suite: 2014 Scheme tests pass, 0 fail; unit suite green; sandbox,\nWASM, and x86_64-linux cross-compile verified.\n\nCloses #1856\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix stale primitive-registration docs (CodeRabbit)\n\n`reg()` has had no caller outside `registerAll`/`registerSandboxed` looping\nover `all_specs` for some time, but CLAUDE.md and src/CLAUDE.md still told\ncontributors to call it from a `registerXxx` function — which, after the\nprevious commit added the spec-table step beside it, left CLAUDE.md\ndescribing two registration workflows, one of which does not exist.\nBoth now describe the spec table alone.\n\nThe /add-builtin skill only mentioned `INTERNAL`; it now distinguishes it\nfrom `INTERNAL_PUBLIC` the way CLAUDE.md and docs/dev/adding-features.md\nalready do.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:10:13+05:30",
          "tree_id": "2c48981d86056b3b6c5e5f355dff2deaf3da8be4",
          "url": "https://github.com/kaappi/kaappi/commit/5ac7369522e55d0bf4d5269079d1ab488548069d"
        },
        "date": 1785403553400,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.227755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.265657,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.599782,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.984523,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004969,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311196,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057363,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.654206,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223407,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.586201,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290857,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809233,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.59505,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043186,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ed5255ec942b95fe3601dc043e00e1249ad3b244",
          "message": "Unwind the GC root stack when an error escapes the pipeline (#1858)\n\nThe canonical pushRoot/try/popRoot rooting pattern leaks its root when the\n*protected* allocation is the one that fails: the error unwinds past the\npopRoot, and nothing else ever lowers root_count. The stack was left holding\nthe address of a local in a frame that no longer exists, which the next\ncollection dereferences — usually a garbage flonum under NaN-boxing,\noccasionally a plausible heap pointer. The extra entry also shifts the stack,\nso every `defer popRoot()` still to fire on the unwind path removes the wrong\nentry.\n\nThis is a property of the pattern, not of any one function, so fix it once at\nthe boundaries that hand a pipeline error back to a caller which keeps\nrunning: the four compileExpression* entry points, vm_eval.eval, and\nvm_calls.execute snapshot gc.root_count on entry and truncate back to it on\nerror. execute truncates inside its error branch rather than by errdefer\nalone, because that branch runs pending dynamic-wind after-thunks — which\nallocate — before returning. Per-site errdefers were the alternative: ~340\nedits of exactly the defer-near-a-loop LIFO footgun gc-safety.md warns about,\nwhich is how the compileLetSyntax bug fixed in #1853 happened.\n\nTruncation only ever shrinks. A depth below the snapshot is an over-pop, and\nre-rooting those slots would resurrect pointers into frames that have since\nreturned — the very bug this removes.\n\nReaching these sites needed a new test lever. gc.memory_limit is an absolute\nwatermark that only trips once a form *retains* more than its headroom, so it\nfails within the first few allocations and never reaches the expander (46\nfailures over 12,500 tries, zero leaks); FailingAllocator has its own\ndocumented deep-pipeline limitation. gc.oom_countdown fails the n-th\nallocation instead, gated on builtin.is_test so it compiles out everywhere\nelse. Sweeping it found the leak in exactly the two expander_instantiate.zig\nellipsis sites flagged in the #1853 review — 10 of 54 and 12 of 48 injected\nfailures — while every other shape swept (records, libraries, let-syntax,\nquasiquote, guard-caught primitive errors, dynamic-wind unwinding, call/cc)\nwas already balanced. Post-fix all are zero, and 3 of the 6 new tests fail\nwithout the fix.\n\nRecovery within a still-running form stays uncovered at primitive\ngranularity: snapshotting per native call would load the interpreter's\nhottest path for a hazard no primitive currently has. Documented in\ngc-safety.md and docs/dev/gc-safety-and-error-handling.md so a future\nunbalanced primitive is recognized as a real hazard.\n\nCloses #1855\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T09:35:31Z",
          "tree_id": "01b0d834ac52bd7e7e2f696144c97487e325ba9c",
          "url": "https://github.com/kaappi/kaappi/commit/ed5255ec942b95fe3601dc043e00e1249ad3b244"
        },
        "date": 1785406535845,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.940655,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.439171,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561309,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.848459,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004935,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044399,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296764,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054947,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.293547,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.166536,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507953,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30455,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.721641,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63592,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044514,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "138857555a5aa83d8f1a5231e52a913d7a3154a1",
          "message": "Correct the three \"add a built-in procedure\" docs (#1863) (#1865)\n\n* Correct the three \"add a built-in procedure\" docs (#1863)\n\nAll three drifted far enough that two of them taught code that cannot\ncompile, so a contributor following them hit errors before reaching a\nreview. Rather than repeat the same content three times, make\ndocs/dev/adding-features.md the one detailed reference and reduce\nCLAUDE.md and the /add-builtin skill to checklists that defer to it.\n\nThe symbol names were the load-bearing errors. `primitives.gc_instance`\nand `primitives.vm_instance` do not exist and never did; the real\ndeclarations are the `memory.gc_instance` and `vm_mod.vm_instance`\nthreadlocals that all 31 primitives files already reach through those\nmodule names. The skill had a third spelling, bare unqualified\n`gc_instance`, which resolves in no primitives file at all.\n\nThe higher-order sample was wrong in a way the issue did not catch:\n`vm.callValue(proc, args_slice)` has no such method on VM, and the free\nfunction `vm_calls.callValue` is register-based — `(vm, callee, base,\nnargs)`. The slice-taking entry point is `vm.callWithArgs`. Since\nPrimitiveError and VMError are both aliases of errors.KaappiError, the\nsample now propagates the callee's error instead of flattening it to a\nTypeError and discarding the detail.\n\nThe skill also taught `return PrimitiveError.TypeError`, which the format\nCI job exists to prevent, so following the documented pattern broke the\nbuild. All three now teach `primitives.typeError(proc, expected, got)`\nand mention the expect* wrappers and the `// bare-ok:` opt-out. That\nguard's baseline was 91 against a current count of 20, leaving room for\n71 regressions; re-tighten it to 20 so it bites again.\n\nRemaining fixes: tests go in one of the 44 src/tests_*.zig files via the\ntesting_helpers (`th.`) API, not the \"src/vm.zig test section\" — vm.zig's\nsingle test block only pulls sibling modules into the test build and\nholds no assertions. Drop the step pointing at STATUS.md, deleted in\ncfe013ce. Correct the primitives table from 26 to 31 and add the 9 files\nit never listed, the stale src/vm.zig:37 and src/primitives.zig:182\nthreadlocal citations, and src/CLAUDE.md's test-file count.\n\nEvery sample was verified by compiling it: each was added verbatim as a\nreal primitive plus a th.expectEval test, built, run, and then reverted.\nThe documented error text is the observed output.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: undeclared `result` in sample, domain-file count\n\nThree findings from CodeRabbit, all valid.\n\nThe skill's step-1 sample returned `types.makeFixnum(result)` with no\n`result` in scope — inherited from the old skill and carried forward\nunexamined, which is precisely the non-compiling-sample defect #1863 is\nabout. Replaced with the computed body already verified in\ndocs/dev/adding-features.md, and compiled it the same way: added verbatim\nas a real primitive plus a th.expectEval test, built, ran (6/6), reverted.\n\n`primitives_*.zig` is 30 files; the 31st is `primitives.zig` itself, which\nall three docs explicitly exclude in the same sentence that claimed 31 —\ninternally contradictory. Prose now says 30 domain files. The table header\nstays at 31: it counts rows, and the table lists `primitives.zig` as one.\n\nListing `IndexOutOfBounds` among tags \"returned directly\" contradicted the\npreceding recommendation of `indexError(proc, index, len)` for exactly\nthose failures, for the same attach-the-detail reason typeError exists.\nDropped it from that list and made the preference explicit.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T16:54:12+05:30",
          "tree_id": "e7982b0d61ddd19078d5b4f1911a36efb25c2583",
          "url": "https://github.com/kaappi/kaappi/commit/138857555a5aa83d8f1a5231e52a913d7a3154a1"
        },
        "date": 1785413943358,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.266495,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.827828,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56789,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.004717,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004666,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309417,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056888,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636908,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.208337,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.636028,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.77862,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043665,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5c8480beb583d5e2ec155224bb533fb5e3d76f45",
          "message": "Let a library body reference an unimported global from its top level (#1866)\n\n#1831 gave get_global, call_global, and tail_call_global one resolver\ncarrying a vm.globals fallback, so a library body can reach a global that\nlives there but not in its own lib_env. The fallback is gated on\nFunction.restricted_globals, which compileExpressionInEnv derived from the\ncompile-time restricted_env flag it sets for both of its callers -- and it\nset it on the outer function of the form only, leaving every closure inside\nwith the field's false default.\n\nSo the same reference still resolved by syntactic position, one level up\nfrom what #1831 fixed: a library's (define v (cadar ...)) raised \"undefined\nvariable\" while the identical reference inside a lambda in the same body\nworked. It had the mirror hole too, which is why the flag could not simply\nbe flipped: for a restricted (environment ...), where withholding\nvm.globals is the point, those nested closures got false as well, so the\nrestriction held at the eval'd expression's top level and leaked through a\nlambda.\n\nMake it a property of the environment instead. compileExpressionInEnv takes\nan EnvKind naming which caller it serves -- a library body, which must keep\nthe fallback, or an R7RS restricted environment, which must not; the two\nhand it structurally identical env maps, so the distinction is not\nrecoverable from the map itself -- sets the flag before compiling, and\ninitChild copies it onto every nested function alongside the env it\nqualifies. gc_deep_copy carries it too, so a closure crossing a thread\nboundary is no leakier than the original.\n\nCompiler.restricted_env keeps its separate, compile-time-only meaning:\nglobals is a partial map, so IR.isRedefined must not read a missing name as\na known primitive. True for both kinds -- its comment claimed otherwise,\nwhich had been wrong since library bodies started setting it.\n\nCloses #1860.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T17:15:11+05:30",
          "tree_id": "41068b345a7918405ec9615ba5fbaa1d42ea33f0",
          "url": "https://github.com/kaappi/kaappi/commit/5c8480beb583d5e2ec155224bb533fb5e3d76f45"
        },
        "date": 1785415059004,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.276233,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.768727,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.617116,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.020453,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004994,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0475,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319253,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057818,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.695021,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223145,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.630102,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.289365,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.848658,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.688833,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045795,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "053282aeda7cb7f0e80a6ebd9765434bafd0dba7",
          "message": "Free the fiber scheduler when its setup allocation fails (#1869)\n\nensureScheduler takes the FiberScheduler from the raw allocator, then runs\ntwo more fallible steps — the main fiber's allocFiber and addFiber — before\nvm.scheduler is assigned. Until that assignment nothing owns the struct, so\na failure in either step returned with it neither destroyed nor stored,\nleaking both the struct and the managed waiter_index map init() built inside\nit. The reactor block directly below already cleaned up after itself; this\nmakes the scheduler block symmetric with its own neighbour.\n\nThe errdefer is block-scoped deliberately. It is discarded when the block\nexits normally, so it cannot fire for a later failure in the reactor block —\nby then vm.scheduler owns the pointer and freeing it would be a double free\nrather than a leak.\n\nSeverity is low on its own (a real OOM during the first spawn, one struct),\nbut the leak blocked writing any OOM-sweep test that reaches a fiber path:\nthe leak check aborts the test before its own assertions run.\n\nTwo regression tests. The first fails the allocation deterministically —\nthe scheduler comes from the raw allocator, which the injector does not\ncount, so oom_countdown 0 lands exactly on the main fiber's allocFiber — and\npins the bug in every build config. The second is the end-to-end sweep over\nthe first spawn; it asserts successes as well as failures, so a future spawn\nthat allocates more fails the test loudly instead of quietly sweeping past\nthe ensureScheduler window and going vacuous.\n\nFixes #1864\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T18:18:37+05:30",
          "tree_id": "c933b3d2ccee9d42b10d35247abf12ba73904592",
          "url": "https://github.com/kaappi/kaappi/commit/053282aeda7cb7f0e80a6ebd9765434bafd0dba7"
        },
        "date": 1785418072826,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.21046,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.86628,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583619,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982115,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004665,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04628,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316775,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057317,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.64402,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596481,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785316,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.56789,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045434,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5400229c25e5e0e0a864e9aeeb0e02bea3f0ad24",
          "message": "Hand the whole enclosing scope to the interpreter when a nested let abandons (#1862) (#1867)\n\n* Hand the whole enclosing scope to the interpreter when a nested let abandons (#1862)\n\nA `let` nested in another `let` that gave up on native compilation\nmid-emission was handed to `kaappi_eval` on its own. That eval resolves\nnames in the global environment, so the outer `let`'s bindings were\ninvisible: the compiled binary died with `undefined variable` on code the\ninterpreter runs fine, or — with a same-named global in scope — silently\nread that global instead, which is worse.\n\n#827 already fixed this class for anything an up-front syntactic scan can\nsee, by declining native compilation of the whole enclosing scope. The\ntriggers here are only discoverable mid-emission and no scan can pre-empt\nthem: more than 32 bindings, more head defines than the scope roots, or an\n`ir.lowerSingleExpr`/`emitNode` failure on a binding initializer or body\nform. #1854 added the last of those, which is what surfaced this.\n\n`bindParamsAsGlobals` is the one chokepoint every whole-form eval fallback\ngoes through, and params, the rest parameter, and upvalues are the whole of\nwhat it can reach — a `let`-local lives in an `alloca` it has no name for.\nIt now refuses when `self.locals != null`, the way it already refuses a\nboxed param it cannot honestly publish. The error abandons the enclosing\n`let` in turn, so the interpreter gets that whole lexical scope in one\npiece. Publishing the locals instead was the other option and is worse: a\nboxed local hits the same by-location problem as a boxed param (#1422), and\nboth of that helper's documented weaknesses — it aliases across\nactivations, and it permanently clobbers a same-named global — would extend\nto let-locals.\n\n`emitLambdaViaEval`'s own locals check is now that same gate one line\nlater, so it is dropped rather than duplicated.\n\nVerified against a pre-fix binary: 11 of the new test's 13 cases diverge\nwithout this and pass with it. The two that pass either way are the\ncoverage guard (a fallback inside a plain lambda frame, where params *are*\npublishable, must still compile the lambda natively — its emitted IR is\nbyte-identical) and the shadow-stack balance check. A 34-program sweep over\nthe shapes this touches moved 7 cases from diverging to agreeing with the\ninterpreter, regressed none, and changed no program's eval-fallback or\nnative-function count: the eval widens from the inner let to the enclosing\nscope rather than replacing native code.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix a stale cross-reference in the #1862 backend note\n\nThe paragraph pointed at \"the mid-emission escape hatch below\", but the\nabandon path is not described further down this document — name\n`abandonLetForFallback` and its triggers directly instead.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:01:29Z",
          "tree_id": "8ad26633e9cbbfc5d395b6974f558abaf4149d81",
          "url": "https://github.com/kaappi/kaappi/commit/5400229c25e5e0e0a864e9aeeb0e02bea3f0ad24"
        },
        "date": 1785422173386,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.946785,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.537929,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.584867,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.852584,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004924,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044643,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294229,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.280049,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.163007,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.503969,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307724,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.696324,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.798772,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04564,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a1301270410a98872534c481387ef84df7d8ff13",
          "message": "Name the expected type, and the right argument, in every type error (#1868) (#1871)\n\nThe `format` job's bare-TypeError ratchet stood at 20. Those 20 were not one\nthing, so this works through them in the four groups the issue identified: 9\ninfrastructure guards gain a `// bare-ok:` reason, 11 become real diagnostics.\nWith none left the ratchet loses its baseline and becomes a plain grep-and-fail,\nso there is no longer a number in CI to keep in step with the source.\n\nA bare return was never as anonymous as it looked, which is what made the\nbacklog easy to leave alone: `vm_calls.mapNativeError` already fills in\n`type error in '<primitive>': got <args[0]>` for any primitive that set no\ndetail. The procedure name survives. What is lost is the *expected* type -- and\nwhenever the offending value is not the first argument, the report confidently\nnames the wrong one. A string-keyed hash table handed a bad key blamed the\ntable itself:\n\n    -  type error in 'hash-table-set!': got #<hash-table size=0>\n    +  type error in 'hash-table-set!': expected string key\n         (this table compares with string=?), got 1\n\nReporting the key instead of the table means the hash-table key path has to know\nwhich procedure it is serving, so `proc` is threaded through equalForTable /\nhashForTable / findKey / findSlot / rehash / growIfNeeded. A fixed \"hash-table\"\nlabel would have been cheaper and nearly worthless: every call site already\nholds the exact literal one line above, in its own `getHashTable` call.\n\nTwo of the 20 were not type errors at all. R6RS's \"parent is sealed\" and a uid\ncollision both reject an argument whose type is perfectly good, which is what\n`invalid-argument` (KP3007) already describes -- \"a value a procedure explicitly\nrejects\", per its own registry entry. They now report that, via a new\n`primitives.argError(proc, fmt, args)` alongside `typeError`/`indexError`. The\nunknown-elision-lever check joins them for a second reason: `typeError` routes\nits value through `safeValueDescription`, which deliberately never dereferences\nheap payloads, so it renders every symbol as a bare `#<symbol>` and could not\nhave named the one passed.\n\nRegression tests assert the message text, since asserting that an error was\nraised -- or even that it names the procedure -- passes against the pre-fix\nbuild too. That is not hypothetical: the first version of the hash-table\nassertion did exactly that and had to be replaced with a pair that pins both\nthe old wrong answer and the new right one.\n\nWhile placing a `bare-ok` marker on threadStartFn's WASM branch, its comment\nclaimed the `else` was what kept std.Thread.spawn out of the wasm32 build. It\nis not. A `@compileError` canary in threadStartImpl fires under neither\n`if/else` nor a plain early return, though one in threadStartFn itself does\nfire: the pruning comes from the comptime-true branch returning\nunconditionally, not from the branch structure. Comment corrected, `else` kept.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T21:28:21+05:30",
          "tree_id": "3efdccc8c2a3b74a8f43b5eee6905a6047e2ff52",
          "url": "https://github.com/kaappi/kaappi/commit/a1301270410a98872534c481387ef84df7d8ff13"
        },
        "date": 1785429660408,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.323705,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.046186,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597107,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.017648,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005077,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047193,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311865,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057113,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.789,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225132,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616054,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287421,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782857,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.675602,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043959,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "eed2ea6fc8eb9a42f7209d7f2531af66a30e61f2",
          "message": "End a timed wait whose deadline the dispatch tick already popped (#1870) (#1873)\n\n`runSchedulerStep` evaluates `!ctx.isDone() and !me.timed_out`, then calls\n`scheduleForDispatch()`, whose own per-tick `runReactorTick()` pops expired\ntimers. When that tick pops *this* fiber's deadline, `wakeReadyFiber` sets\n`me.timed_out` and the entry leaves the timer heap — but the loop guard has\nalready been spent on the pre-tick state, so the idle branch went straight\ninto `parkOnReactor` with nothing left to bound `reactor.poll()`. The\nfiber's own `shared_waiters` entry keeps `hasRunnableFibers()` true, so the\n\"nothing can ever happen\" early return is skipped too, and the poll blocks\nuntil some unrelated cross-thread notify arrives. The loop guard never gets\nits turn, because the park never returns.\n\nThat is the srfi120.scm flake: a timer thread parked on its control channel\nfor a 30 ms task would sleep indefinitely and only wake when the caller's\nown `timer-cancel!` message rang its notifier seconds later — by which point\ndelivery-wins hands it the `stop` message and the task never runs at all.\nWindows is where it showed up because `WaitForMultipleObjects` returns\nspuriously often enough (an auto-reset notify event left signalled by an\nearlier `SetEvent`) to put a loop iteration exactly where it needs to be:\npast the guard, with the deadline expiring during the tick.\n\nMeasured on the Windows ARM64 reference VM, one `(srfi 120)` timer per\niteration: 4 wedges in 13,500 iterations before, 0 in 9,000 after. macOS\nnever reproduced it in 7,000.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T21:52:14+05:30",
          "tree_id": "71c991a9c4b1e000442a702a133f95ee60802fb9",
          "url": "https://github.com/kaappi/kaappi/commit/eed2ea6fc8eb9a42f7209d7f2531af66a30e61f2"
        },
        "date": 1785431274194,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.036862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.295983,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433564,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.249385,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003781,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034661,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227601,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042621,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.853378,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.885467,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.178073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.233648,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.301973,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.365367,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035083,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b1f4b9c20761581a51434dcd42e81063e140b03",
          "message": "Scope the procedure shorthand's internal define to its enclosing body (#1861) (#1872)\n\n* Scope the procedure shorthand's internal define to its enclosing body (#1861)\n\n`(define (f …) …)` inside a natively compiled `let` or lambda body compiled to\na global define, so an internal definition overwrote an outer one of the same\nname instead of shadowing it — and a helper referencing an enclosing binding\ncompiled to a global function whose body looked that binding up as a global,\nkilling the binary on code the interpreter runs:\n\n    (let ((a 3)) (define (h n) (* n a)) (h 5))   ; undefined variable 'a'\n\n#819 fixed this class for the symbol form and #1854 gave it a rooted slot, both\nin `emitDefine`. `lowerDefine` turns a pair target into a `.passthrough`, so the\nshorthand never reaches that path; it landed in `emitPassthrough`, whose two\npaths both define a global — `kaappi_define_global` when the body compiles\nnatively, and otherwise an `emitEvalExpr` that runs in the global environment.\n\nDecline the form whenever a lexical scope is active, so the enclosing scope goes\nto the interpreter whole (#827's rule). The gate is `inLexicalScope()`, not\n`locals != null`: a lambda body has no locals map and is lexical because of its\nparams, and had the identical bug. A `let` body abandons via `emitLet`; a\nfunction body fails `emitLambdaFunction` so the whole define falls back.\n\nDeclining also drops the name from `native_fns`/`rebound_globals` first. This\ninterpreter rebinds a body define that is *not* at the head of its body as a\nglobal, and a later call site that kept its direct call to the top-level\nfunction of the same name cannot observe that.\n\nCompiling it as a native local binding is the fuller fix, but it needs the\nclosure value in a rooted slot (#1854's machinery extended to a lambda-valued\ndefine) plus a way to keep the inner name out of the module-wide `native_fns`\nmap, where it would capture direct call sites outside its own scope.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Assert the direct-call binding without assuming the tailcc fast entry\n\nThe #1861 direct-call test matched only `call tailcc i64 @`, which exists only\nwhere `llvm_emit.fast_tailcalls_supported` — aarch64 and x86_64. On the\nQEMU-tier arches every direct call is the uniform array ABI instead, so the\nassertion passed vacuously and its own positive control failed, breaking\nppc64le-test, riscv64-test and s390x-test.\n\nMatch the callee position against all three spellings instead: the fast entry\n`@r{i}.fast`, and the uniform entry under a reserved name (`@r{i}`) or an\nunreserved one (`@lambda_{i}`). Anchoring on what follows `call [tailcc ]i64 `\nkeeps the `ptr @r0` *argument* of a kaappi_create_native_closure — present in\nboth the fixed and control programs — from being read as a call to it.\n\nVerified both ways by forcing `fast_tailcalls_supported` to false locally: the\ntest passes under either ABI, and still fails under either when the invalidation\nit guards is removed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T22:26:06+05:30",
          "tree_id": "6a3844a99afc11b09419532e540e51ccc0d35412",
          "url": "https://github.com/kaappi/kaappi/commit/6b1f4b9c20761581a51434dcd42e81063e140b03"
        },
        "date": 1785432971533,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973066,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.302041,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573159,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.864319,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004874,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044883,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300815,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055648,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.381858,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.167287,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510843,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299486,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.694847,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.618973,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044446,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f47679a7a0b1dede740a84280be47e3af5cb640",
          "message": "Settle the vm_instance/gc_instance guard tag, and write the rule down (#1875)\n\nThe ~450 threadlocal guards had drifted into a 46/34 TypeError/OutOfMemory\nsplit for the same \"the runtime is not initialized\" failure — two lines apart\nin primitives_hashtable.zig, and arbitrary in both directions (21 TypeError\nsites allocate; 13 OutOfMemory sites never do). There was already an implicit\nrule holding most of them together, but it was nowhere written down, which is\nhow the rest drifted.\n\nBoth halves of the fix:\n\nRule 1, unchanged and now stated: a guard returns the tag the function was\ngoing to return anyway, just without the formatted detail. That covers\ntypeError/indexError/argError/raiseDivByZero and the arity helpers, and — at\nscale — the 348 gc_instance guards in allocating functions, where no GC means\nthe allocation the function exists to perform cannot happen, so OutOfMemory\n*is* its error. None of those change.\n\nRule 2, the decision this issue asked for: with no natural tag, InvalidBytecode.\nA null threadlocal is an implementation-invariant violation, and that is the one\nKaappiError variant that means so. runtimeErrorCode already maps it to\n.internal_error (KP9001), whose registry template is the whole message the user\nsees since these guards set no detail — \"internal error … please report it\".\nOutOfMemory would send the reader after heap size; a bare TypeError is worse,\nbecause mapNativeError dresses it up as `type error in '<proc>': got <args[0]>`\nand so blames a real argument (the trap #1868 was about).\n\n82 sites move. The one-offs go with them: primitives_control's two no-VM\nfallback blocks retag whole rather than one return of four, and expander.zig's\nodd `error.TypeError` spelling becomes `error.InvalidBytecode`, which is a tag\nthat file can use honestly. Sites the issue blessed keep theirs, including\nbootstrapStub, whose guard mirrors its function's own tag.\n\nKP9001's template said \"internal compiler error\"; KP9xxx is stage .internal and\nthe code is now reached from the runtime too, so it is \"internal error\", with\nthe uninitialized-runtime path named in the explanation. One assertion pins\nruntimeErrorCode(InvalidBytecode) → .internal_error, since ~80 sites depend on\nthat arm and losing it would silently downgrade every one of them to the\nuncategorized catch-all.\n\nThe rule itself lands in docs/dev/gc-safety-and-error-handling.md, with the\nrejected alternatives named and one seam flagged: the raise* helpers ending in\nExceptionRaised split across both rules, because ExceptionRaised is the one tag\na guard cannot borrow — it promises vm.current_exception was set, and the guard\nfired precisely because there is no VM to set it on. adding-features.md, the\nadd-builtin skill, .claude/rules/gc-safety.md and the CI gate's own help text\nall taught the retired pattern by example, so they move too.\n\nNo behavior change: the threadlocals are set during VM init, before registerAll,\nso none of these guards fires in a working build.\n\nCloses #1874\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T23:39:46+05:30",
          "tree_id": "f793cadf890fe52bd056b5af462cbf871d89b081",
          "url": "https://github.com/kaappi/kaappi/commit/9f47679a7a0b1dede740a84280be47e3af5cb640"
        },
        "date": 1785437290587,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.275755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.730863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573825,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.976157,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004688,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046403,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314943,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057281,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650338,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231441,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589625,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27321,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.792627,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596818,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04317,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d529fdcc8d584641f05c69b0d7bedbd530af85be",
          "message": "Report an uninstalled bootstrap as KP9001, not a caller type error (#1877)\n\n`primitives.bootstrapStub` stands in for the 9 procedures whose real bodies\nare Scheme installed by `vm_bootstrap.install()`. It fired `TypeError`, which\n`diagnostics.runtimeErrorCode` maps to KP3002 — telling `--diagnostics=json`,\nthe LSP and `error-object-code` that the caller passed a bad argument type.\nThe truth is the opposite: Kaappi is mis-initialized, and nothing the user\ndoes to their program will help. That is KP9001's job, and its registry text\n(\"please report it with the program that triggered it\") is the right\ninstruction. Both lines are `InvalidBytecode` now.\n\nThe two were not equally wrong. The second sets a detail first, so only the\ncode misled. The first — the no-VM guard — set none, so `mapNativeError`\nsynthesized `type error in 'map': got <args[0]>`, naming a real list element\nas the culprit: wrong code *and* wrong message, the exact trap #1868 closed\neverywhere else. Both `bare-ok` annotations go away with the tag.\n\n#1874 left this alone for a good reason: its rule is that a guard returns the\ntag its function was going to return anyway, and the guard did mirror the\nfunction. The function's own tag is a separate question, and this answers it.\nBoth prose sites that recorded bootstrapStub as a settled Rule 1 keeper are\nupdated, with the distinction written down — a correct guard on a wrongly\ntagged function reads exactly like a site the rule has already cleared.\n\nThe stub is unreachable from every shipped entry point (every one calls\n`install()`; `runtime_exports` bails out if it fails), so this is a tripwire\nfor a new embedding that forgets the call — precisely when a code pointing at\nKaappi rather than at the user's arguments is worth the most. The existing\n#1375 regression test is kept and retargeted, and now also derives the\ndiagnostic code from the error the eval actually returned, so a silent\nre-tagging fails it; `runtimeErrorCode`'s own table stays pinned separately\nin tests_diagnostics.zig.\n\nCloses #1876\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T05:54:19+05:30",
          "tree_id": "2e1d8cfe47b9df35d8b96d4cfc768a8aabdb8371",
          "url": "https://github.com/kaappi/kaappi/commit/d529fdcc8d584641f05c69b0d7bedbd530af85be"
        },
        "date": 1785459831428,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.059243,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.600001,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.437131,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.232096,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003879,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034503,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228697,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042366,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.793723,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.888163,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.179701,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.243072,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.309579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.415215,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034944,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7bd728d4a102b667ef52b211e2c4e4a635749bb9",
          "message": "Report a missing VM as an internal error in the last four guards (#1878)\n\nkaappi#1874 settled what a `vm_instance orelse` guard should return, but four\nsites kept `TypeError` through the sweep. Rule 1 vets a guard against its own\nfunction and never vets the function, so a correct-looking guard on a\nwrongly-tagged function reads exactly like a site the rule has already cleared\n-- the same trap kaappi#1876 hit with `bootstrapStub`.\n\nThe three `vm.zig` hooks are the easy half: they return `anyerror`, so there\nwas never a tag they were going to return anyway. `applyFn` is the one worth\narguing. `apply` does raise real type errors, for a non-procedure and for an\nimproper final list, which is why its guard looked settled. It isn't: Rule 1\ncovers a helper that fetches the VM only to attach a message to an error it\nwas already committed to raising, and `apply` fetches it in order to call the\nprocedure. A null threadlocal means `apply` cannot run at all. The\n`gc_instance` line under it keeps `OutOfMemory` -- two adjacent guards, one per\nrule.\n\nOnly `apply`'s tag is user-visible. It is a primitive, so a bare `TypeError`\nreached `--diagnostics=json`, the LSP and `error-object-code` as KP3002 \"you\npassed a bad argument type\" for a condition no program can cause; it is KP9001\n\"please report it\" now. The three hooks' callers collapse everything but\n`OutOfMemory` into `InvalidSyntax`/`TransformerFailed`, so their tag is read by\nthe next maintainer rather than by a diagnostic -- which is precisely why it\nneeded pinning, an unpinned readability-only tag being what drifted here in the\nfirst place.\n\nThe doc gains both decisions and the CI gate's two blind spots, with one\ncorrection to how they have been described: there are three spellings of this\nerror in `src/`, not two. `ffi.zig` declares inline `error{TypeError}` sets and\nuses neither the `PrimitiveError` nor the `VMError` alias, and it holds 27 of\nthe 35 out-of-scope sites -- so a grep widened from the two-alias description\nmisses all of them, which is the same blind-spot class the warning is about.\nWidening the gate stays out of scope; those 35 are real error conditions\nneeding triage, not threadlocal guards.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T01:18:07Z",
          "tree_id": "801ea451e4eb32d3cf37a2254a5787852c401962",
          "url": "https://github.com/kaappi/kaappi/commit/7bd728d4a102b667ef52b211e2c4e4a635749bb9"
        },
        "date": 1785463138959,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.243356,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.830061,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583153,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.963405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004711,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314667,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057662,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.66787,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230955,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589988,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279296,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797338,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.625157,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042974,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f1c323f402bd5265086faa059bd861df592c4c4",
          "message": "Say what R6RS rejected, instead of raising a bare type error (#1880)\n\n`define-record-type`'s R6RS clause syntax had two conditions that reported\n`error[KP3002]: type error` and nothing else -- no procedure, no expected\ntype, no value, the three things KP3002's own registry entry promises. Both\nreproduce in five lines: a sealed parent rtd, and a `nongenerative` uid\nalready bound to a non-equivalent type.\n\nNeither is a type error. Both arguments are of a perfectly good type and the\nprocedure rejects them anyway, which is what KP3007 (invalid-argument) is\nfor -- and R6RS's own wording for the first is \"an exception is raised if\nparent is sealed\", nothing about types.\n\nThe procedural half of the same two rules (`%make-record-type-descriptor`)\nhas been getting this right since #1868, so the fix is to stop stating the\nrule twice: `RtdShape`, `sealedParentError` and `reuseNongenerativeRtd` in\nprimitives_srfi237.zig now hold both the equivalence test and its wording,\nand the syntactic and procedural routes share them. Only the procedure name\ndiffers -- a caller who wrote `define-record-type` should not be told about\nthe internal primitive it desugars to. A uid collision now names the one axis\nthat actually differs rather than listing every axis it might have been.\n\nReading those two functions turned up a third condition of the same shape\nthat #1880's census could not see, because it is spelled as a `return switch`\narm rather than a bare return: more than 255 fields once a parent's are\ncounted. Its procedural half was the worse of the two -- a bare TypeError out\nof a primitive is not anonymous, `mapNativeError` fills the detail in from\n`args[0]`, so it confidently blamed the type's *name* for a limit the field\nlist broke.\n\nAlso folds `callFfi`'s four call sites into one `vm_calls.mapFfiError`. Two\nof them supplied a fallback message when callFfi returned without setting a\ndetail and two did not, and the two that did not are the hot ones. That is\nlatent today -- callFfi guarantees a detail on every path it can currently\nfail through -- but one shared mapper is cheaper than separate copies of the\nsame guard staying in sync. Worth knowing for anyone testing this: the four\nsites are *not* reached by direct call / apply / map, which all land in\nvm_calls.zig; the two vm_dispatch.zig sites are the tail-call and tail-apply\nopcodes, so the regression test uses tail-position forms.\n\nThe two remaining bare returns outside ffi.zig already call `setErrorDetail`\non the line above and are now annotated as such, leaving every non-FFI site\nin src/ either fixed or carrying a stated reason.\n\nNot done: ffi.zig's 27 sites (the issue's Group D), which are internal\npass/fail signalling behind `validateArgsDetailed` -- retagging them would\nchange nothing a user sees and would break the caller's switch. The\n`format` job's grep is unchanged; widening it is now a single question about\nthose 27 rather than a mixed bag.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T08:52:21+05:30",
          "tree_id": "7ea2e112ab6fae5ee525bfdd6b07ff6533a21058",
          "url": "https://github.com/kaappi/kaappi/commit/9f1c323f402bd5265086faa059bd861df592c4c4"
        },
        "date": 1785470289832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300079,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.89231,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580175,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046457,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311103,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057056,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.616138,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232008,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280976,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797544,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.486603,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046708,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3fbfc0a575efff60ad66152ef7b62e5b3e799268",
          "message": "Let a record's constructor be named `fields` or `parent` (#1882)\n\nSRFI 237's R6RS clause grammar is ambient — `(scheme base)`'s\n`define-record-type` accepts it with no `(import (srfi 237))` — so the two\nsyntaxes are told apart structurally. The detector inspected only the head\nof the form's 2nd element, which in R7RS syntax is the *constructor's*\nname, so `(define-record-type point (fields x y) point? (x point-x) (y\npoint-y))` was parsed as R6RS and rejected. Nothing in such a program\nsignals that the R6RS grammar is in play, and the diagnostic was a bare\nKP2001 whose follow-on `undefined variable 'fields'` pointed away from the\ncause.\n\nThe 3rd element separates the grammars unambiguously: R7RS always has one\nand it is always the bare-symbol `<predicate>`, while an R6RS `<record\nclause>` is always a list — or absent, when there is at most one clause.\nAdding that as a second condition is a pure narrowing, so every R6RS form\nkeeps its path and every malformed form keeps its diagnostic; only valid\nR7RS forms move.\n\nTwo paths beyond the top-level handler shared the misdetection. In a body\nit aborted the internal-define scan, so sibling `define`s written after\nthe record lost their mutual visibility. In a library body, where the R6RS\ngrammar is rejected outright as a documented top-level-only feature, the\nwhole library failed to load.\n\nTests: a compliance suite with a library fixture (18 assertions, 8 of them\nfailing before the fix) plus three unit tests — the R7RS one demonstrates\nthe fix, the R6RS-detection and malformed-form ones bound it.",
          "timestamp": "2026-07-31T11:20:10+05:30",
          "tree_id": "998eea705c31025c9b6744147610e7f0e8726ec9",
          "url": "https://github.com/kaappi/kaappi/commit/3fbfc0a575efff60ad66152ef7b62e5b3e799268"
        },
        "date": 1785479085311,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.055786,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.203136,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.43785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.215485,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003795,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034516,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231392,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042579,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.774703,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.917524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.175114,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237565,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.312865,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.381513,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035481,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "40f04a6db595e198ccd8008a513184ab9ddd798a",
          "message": "Release v0.22.1\n\nBug fixes and diagnostics. Three native-backend correctness fixes: an\ninternal define in a `let` body was never GC-rooted (#1854), the procedure\nshorthand `(define (f ...) ...)` compiled to a global define (#1861), and a\nnested `let` falling back to the interpreter lost the enclosing scope\n(#1862). Plus the `(srfi 120)` Windows wedge (#1870) and a library body that\ncould not reference an unimported global from its own top level (#1860).\n\nThe user-visible surface change is #1856: `(scheme base)` no longer exports\n22 `%`-prefixed internal primitives, so a user library defining its own\n`%name` loads again under v0.22.0's R7RS 5.2 enforcement. The ones portable\n`.sld` files need move to a new `(kaappi primitives)`.\n\nDiagnostics: every type error now names the expected type and the right\nargument (#1868), an uninitialized runtime reports KP9001 instead of a\ncaller type error (#1874/#1876/#1878), and two R6RS record conditions\nreport KP3007 rather than a bare KP3002 (#1880).\n\nBuilt-in procedures 690 -> 689 (`%length` deleted). The count command in\nthe release skill was undercounting by 2 -- it greps only for literal\n`.name = \"...\"`, and two entries converted to named constants this cycle --\nso it now resolves those too.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T11:50:24+05:30",
          "tree_id": "dc5bbbf2a11807643f675b30b34648ed25440706",
          "url": "https://github.com/kaappi/kaappi/commit/40f04a6db595e198ccd8008a513184ab9ddd798a"
        },
        "date": 1785482014724,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.582863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571659,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.978246,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004648,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046357,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310691,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057033,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.602668,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572815,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278719,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800123,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.620418,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043836,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "261fde5fad3c3d65cda83fdd507ce5d14cee729a",
          "message": "Gate publishing on CI, and ask for a changelog entry while it is cheap (#1885)\n\nv0.22.1 went public at 06:35:24 with ci.yml still running on the same\ncommit, and would have published identically had CI failed. The tag push\nand the branch push start release.yml and ci.yml as two independent runs\nwith nothing between them, so they race and publishing wins. The only\nthing that actually gated that release was a local test run.\n\nA new `ci-gate` job polls for the ci.yml run on the tagged SHA and only\nthe `release` job depends on it, so the 14 platform builds still run in\nparallel with CI -- gating costs no wall clock unless CI is the long pole.\nAbsence of a run is retried rather than treated as failure, since a tag\npushed alongside its branch can beat its own CI run into existence; a\nconcluded-but-not-successful run (including `cancelled`) refuses to\npublish. The workflow gains `actions: read`, without which the poll would\n403 -- declaring any `permissions:` block zeroes every scope not listed.\n\nThe changelog half addresses a different recurring miss: `[Unreleased]` is\nreconstructed from `git log` at release time rather than written as the\nwork lands, and had 14 of 100 commits at v0.22.0 and 5 of 16 at v0.22.1.\nA PR touching src/ or lib/srfi/ without touching CHANGELOG.md now fails,\nwith a `no-changelog` label for changes that are genuinely not\nuser-visible. Labels are read live via the API rather than from\ngithub.event, because re-running a job replays the original event payload\n-- a label added in response to the failure would otherwise be invisible\nto the re-run, making the documented escape hatch a dead end.\n\nAlso corrects two things the v0.22.1 run surfaced in the release skill:\nthe build-target list said 12 where the matrix ships 14 (s390x and\nppc64le were missing, both present in the released assets), and the\nNetBSD denormal probe imported (srfi 144), which needs ~/.kaappi/lib and\nso fails on a fresh VM as `undefined variable 'fl-least'` -- reading as a\ndenormal regression on the one platform whose FPCR fix it guards. The\nlibrary-free `5e-324` spelling tests the same thing with no import.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T13:08:23+05:30",
          "tree_id": "b2a7bbed1d42d32efd3baa3a2e7685fb4d8c6579",
          "url": "https://github.com/kaappi/kaappi/commit/261fde5fad3c3d65cda83fdd507ce5d14cee729a"
        },
        "date": 1785485901359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.318459,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.998063,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582215,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982443,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004751,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046463,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311828,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057339,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.604341,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231106,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580214,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797204,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626622,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "12588782c29762552483fa03b64786a3232e731b",
          "message": "Rewrite the audit strategy for a codebase that now has fuzzers (#1889)\n\nThe v1 campaign (#1137) closed on 2026-07-05 and its document still\ndescribes what it audited: ~39k lines, 578 procedures, 21 primitives\nfiles, 72 SRFIs. Since its base commit that is 417 commits and +67k\nlines ago. 132 of 162 .sld files and 166 of 200 SRFI tests postdate it,\nso for most of the tree a second campaign is a first audit, not a\nre-audit — and ten primitives files have no audit test at all.\n\nTwo things change the shape of the work rather than just its size.\n\nThe project now runs nightly differential fuzzing with three oracles\n(opt-vs-no-opt, VM-vs-native, Kaappi-vs-Chibi). v1 predates all of it,\nso v2 is scoped explicitly as the complement: fuzzers own crashes and\ntier divergence inside a generated subset, the audit owns breadth and\nanything whose oracle is a document rather than the implementation's\nother half. Without that split the obvious next campaign would spend\nits budget rebuilding harnesses that already run every night.\n\nAnd a large fraction of the remaining work is documentation truth, not\ntesting. Five of the six expander limitations CLAUDE.md lists as open\nare fixed; the eval_fallback_form_names hazard it warns about has\nmigrated to a different, still hand-maintained list; the SRFI 58/163\nexclusions rest on two statements that are now false. An auditor\ntrusting the docs today loses sessions to bugs fixed months ago, which\nis why the truth pass is Phase 0 and not an afterthought.\n\nA seven-agent reconnaissance pass fed the rewrite and is recorded in\nit: 13 reproduced findings against a fully green suite (624/624 Scheme\nfiles, 1395/1395 R7RS assertions). That gap is the campaign's\njustification — the suite is green because it does not ask these\nquestions, not because the answers are right.\n\nThe audit-primitives skill is updated in the same commit because every\nPhase 2 session loads it and it had drifted onto the old\n`try reg(vm, ...)` registration and a 18-of-31 file list.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:02:02+05:30",
          "tree_id": "6cb49d8cb3805204fa855918b2bda28f91a115f7",
          "url": "https://github.com/kaappi/kaappi/commit/12588782c29762552483fa03b64786a3232e731b"
        },
        "date": 1785493530297,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.935647,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.864529,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562005,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.832828,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004842,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044575,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293627,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054868,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.284727,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158065,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.511626,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301755,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.68899,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783272,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046638,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c6040f1802c2e54b7068a0d632a36bb99cfedbb4",
          "message": "Tick Phase 0A and point the tracker at the filed issues (#1904)\n\nThe document calls its progress tracker the single source of truth for\nwhat is done, so leaving 0A unticked after running it contradicts the\nrule the campaign is meant to enforce — the first session to read it\nwould have re-run the baseline and re-filed thirteen issues.\n\nRecords the green baseline, the tracking issue, and the twelve issue\nnumbers. Also notes that reproducing F12 before filing corrected it: a\nflat cdr-cycle prints its label correctly, and only a car-nested cycle\npast the depth limit loses one. The reconnaissance table keeps the\nrepro recipes, since those are what a fixer needs and the issues\nduplicate rather than replace them.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:42:35+05:30",
          "tree_id": "4d609c6de114ec2e3a4175b0615a4302f7baae5e",
          "url": "https://github.com/kaappi/kaappi/commit/c6040f1802c2e54b7068a0d632a36bb99cfedbb4"
        },
        "date": 1785500102341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.942564,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.072483,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560011,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0049,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044633,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293514,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054836,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.29169,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157576,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519576,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685114,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.732877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044263,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6d621fc7f3afe0e9bf713c9810475bf35758014c",
          "message": "Correct six documentation claims that no longer describe the code (#1905)\n\nPhase 0B of the v2 audit campaign (#1901). Every claim was re-verified\nagainst v0.22.1 before being edited, which matters more than usual here:\nthe point of the pass is to stop propagating unverified statements, so\ntaking the reconnaissance report on faith would have reproduced the\nfailure mode it was meant to fix. Two findings changed under that check.\n\nThe native-backend warning was aimed at the wrong list.\neval_fallback_form_names is comptime-derived and self-maintaining; the\nhand-maintained array that can actually cause a silent miscompilation is\nisRejectedFormHead, which is already missing define-property (#1896).\nAnyone adding a form was being pointed at the safe list.\n\nSRFI 148 was recorded as 134 passing with 8 test-expect-fail. It is 142\npassing with none. The reconnaissance also called the test file's header\ncitations dead comments; reading it showed the opposite — the header\ndocuments both fixes accurately and is worth keeping, so the note now\nsays to read it rather than distrust it. Repo-wide there are 6\ntest-expect-fail calls, 4 of them in srfi150.scm, which matches that\nfile's reported count exactly and disproves the claim that two never\nexecute.\n\nThree limitations documented as open are fixed: the let-syntax chain\nproducing define-syntax, library-body shadowing of define-record-type,\nand (already noted elsewhere) the ellipsis leniency. The shadowing note\nnow records the trap that made it look broken — bind a name from the\nmacro's pattern, not one introduced by its template, or hygiene renames\nit and the test fails for an unrelated reason.\n\nThe SRFI 120 corruption claim does not reproduce. Both documented entry\npaths now fail cleanly and deterministically across 10 runs, because a\n<timer> holds a Fiber that gc_deep_copy rejects outright, so the\nsingle-thread constraint is engine-enforced rather than a hazard to\ndesign around. The re-check's limits (macOS, ReleaseSafe, no gc-stress)\nare recorded alongside it — stale claim, not proof the bug never existed.\n\nThe SRFI 58 and 163 exclusions rested on \"SRFI 160 has no implementation\nat all\" and \"SRFI 4 is a purely portable wrapper\". Both are false now, so\neach entry drops to a single reader-ambiguity blocker and both SRFIs\nbecome re-considerable.\n\nFinally, tests/scheme/CLAUDE.md's directory table was missing six suites\nthat exist and run, and said nothing about run-all.sh's globs being\nnon-recursive — the reason tests/scheme/srfi/slow/ has never run (#1900).\nThat stale table is what sent a reconnaissance agent chasing a\n\"tests exist but never run\" headline that turned out to be false.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:45:08+05:30",
          "tree_id": "59aac2a19d1c488ca2527790782f66af787d2428",
          "url": "https://github.com/kaappi/kaappi/commit/6d621fc7f3afe0e9bf713c9810475bf35758014c"
        },
        "date": 1785504205910,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.388724,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.202274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.048954,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047007,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059108,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.624791,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.251477,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612267,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.29035,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.821671,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.624745,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047755,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "61f6e8c48003b4674677737513f975a7eed71233",
          "message": "Phase 2.1: internal-primitive audit — 239 assertions over a 51-procedure surface with no prior tests (#1918)\n\n* Audit the %-prefixed internal-primitive surface (audit v2, Phase 2.1)\n\nEvery registered primitive spec lands in vm.globals regardless of its\n`libs` tag -- only *export* is gated -- so all 60 `%`-prefixed specs in a\ndefault build are callable from a plain top-level script with no import\nat all. 51 of them are reachable that way today; the other 9 are the\npurged `internal_helpers` (8) plus the instrument-only build hooks.\nBetween them they had close to zero mention anywhere in tests/.\n\n239 assertions across the record substrate (R7RS and R6RS/SRFI 237),\nSRFI 160 numeric vectors, SRFI 271 random ports, SRFI 181 transcoded\nports, SRFI 248 unwind handlers, the parameter internals, the SRFI 27\nsubstrate, and the sysinfo probes. Each procedure is probed for arity at\nboth bounds, wrong types in *each* argument position independently, and\nboundary values (negative and just-past-the-limit indices, empty inputs,\nper-kind numeric range ends).\n\nDiscovery only -- no source is changed. 14 assertions are commented out\nbehind `;; FAIL: TBD` markers covering seven distinct defects, each\npaired with an enabled discriminating control that proves the failure is\nspecific rather than a whole-codebase convention. The three cross-tier\nassertions marked \"(fails on wasm32)\" pass natively and fail under\nwasmtime, pinning an index-truncation divergence.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 2.1 FAIL markers at the filed issues\n\nCommitted with placeholders before the issues existed; each now names the\nissue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:08:10+05:30",
          "tree_id": "9d84885761abdb3c4ab8d665babb6ddece93b148",
          "url": "https://github.com/kaappi/kaappi/commit/61f6e8c48003b4674677737513f975a7eed71233"
        },
        "date": 1785505306939,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.944945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.379032,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564248,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844358,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0445,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293462,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054817,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.309844,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158526,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513685,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30613,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.697198,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.803746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046008,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1c3dec04c7ed3571f4a526d2c0fdca6d104abd96",
          "message": "Run the test suites in parallel, and stop sleeping through them (#1887)\n\n* Run the test suites in parallel, and stop sleeping through them\n\n`bash tests/scheme/run-all.sh` took 17.8 min on a 4-core box to do about\n90s of actual work. Two independent causes, fixed here.\n\n**The poll interval.** `wait_with_timeout` polled a spawned child with\n`sleep 1`, so every one of the ~620 spawned units cost a full second of\nwall clock no matter how fast it really was — and 381 of the 566 .scm\nfiles finish in under 50ms. That single sleep was ~93% of the script's\nruntime. The tick is now 0.05s, counted in 20ths of a second so the\ntimeout keeps its exact meaning, with an integer fallback if a platform's\n`sleep` rejects fractions.\n\n**No parallelism.** Each .scm file is already a fresh interpreter with no\nshared state, so `run_suite` now dispatches KAAPPI_TEST_JOBS at a time\n(default: one per CPU; 1 restores strictly-sequential). Workers write\ntheir verdict to a slot and the parent tallies and prints afterwards in\nglob-sorted order, so output ordering and the counters are unchanged. An\naudit of the corpus found no cross-file collisions on fixed paths or\nports before turning this on.\n\nShell suites stay sequential: several call `ensure_runtime_lib`, which\nruns `zig build lib` into the shared zig-out/lib, so concurrent scripts\nwould race over one output archive. They are now the larger half of the\nremaining wall time.\n\n`kaappi test` gets the same treatment via `-j`/`--jobs`, which its own\ndocs already anticipated. Worker threads claim files from an atomic\ncounter while the main thread reports the completed prefix in file order,\nso verdicts and output ordering are identical at any job count. The emit\npath now travels in the child's own envp: setenv on the parent before\neach fork is a single mutable global shared by every in-flight worker,\nand two concurrent spawns would have sent both children to the same path\nand lost a result. Windows stays at one job, where that env is still\ninherited from the parent.\n\nMeasured on 4 cores, all three producing identical results\n(2019 pass, 0 fail):\n\n    run-all.sh, before                1070s\n    run-all.sh, KAAPPI_TEST_JOBS=1     425s   2.5x\n    run-all.sh, default (4 jobs)       279s   3.8x\n    kaappi test tests/scheme/srfi     18.5s -> 4.6s   4.0x\n\ntests/scheme/test-runner/jobs.sh pins the parity down by diffing whole\ntranscripts between --jobs 1 and --jobs 4, including a deliberately\nslow-first fixture so a reporter that emitted in completion order would\nfail even though its totals stayed correct.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Address review: validate KAAPPI_TEST_JOBS, cover resolveJobs, sharpen docs\n\nThree findings from CodeRabbit on #1887, all valid.\n\n`KAAPPI_TEST_JOBS` was never validated — only `detect_jobs`'s own output\nwas. `[[ $running -ge $JOBS ]]` evaluates its operands arithmetically, so\na non-numeric value is silently 0: `KAAPPI_TEST_JOBS=abc` did not fail,\nit quietly serialised the run with a spurious `wait` per file, and still\nreported success. A typo in a CI env var should not cost a 4x-slower\nsuite that looks fine. Bad values now exit 2 with the offending value\nnamed. `0` is rejected in `detect_jobs` too, where it would have been\npassed through as a valid count.\n\n`resolveJobs` is pure and encodes the platform policy the rest of the\nfeature rests on, so it gets direct unit coverage: zero and one file,\na request above the file count, an explicit `--jobs 1`, and auto —\nwith the Windows and single-threaded expectations gated on the same\ncomptime conditions the function itself uses.\n\nThe `--jobs` doc claimed output is identical at any job count without\nnoting that durations obviously are not; it now says the test normalises\nthe `…ms` fields and then requires a byte-for-byte match, which is what\njobs.sh actually does.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Add the CHANGELOG entry the `changelog` CI job requires\n\nThe PR touches src/, and `kaappi test --jobs` is a new user-facing flag,\nso this is a real entry rather than the `no-changelog` escape hatch.\n\nRecords the flag itself and, under Fixed, the emit-path race it required\nclosing — worth stating separately because it was a latent correctness\nbug in shipped code, even though nothing could reach it while spawns\nwere serialised.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n---------\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:19:37+05:30",
          "tree_id": "9a209b851b025a51669a094eae25d72bc844b930",
          "url": "https://github.com/kaappi/kaappi/commit/1c3dec04c7ed3571f4a526d2c0fdca6d104abd96"
        },
        "date": 1785506313723,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.346949,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.970683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.590433,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982932,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004741,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047208,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318695,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05739,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.661153,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231094,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616613,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284512,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79793,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611677,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044051,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2903f3532d14576629b5dcd949643a81aea2371d",
          "message": "Phase 1A: reader exactness audit — 128 assertions, 5 new bugs including a process-abort panic (#1917)\n\n* Add Phase 1A reader-exactness audit tests\n\nAudit v2 Phase 1A: `#e`/`#i` over the i64 boundary and reader vs\n`string->number` parity, against R7RS 6.2.5, 6.2.7 and 7.1.1.\n\n128 assertions pass; 39 are commented out with `;; FAIL:` markers — 7 for\nthe known #1891 and 32 for six findings this pass reproduced. Every\ndisabled group keeps an enabled discriminating control beside it, so the\nfile still proves the neighbouring path works.\n\nThe findings share one cause: `applyExactness` exists twice, in\n`reader_tokens.zig` and `primitives_numeric.zig`, with different\nstrategies. `string->number` rebuilds the value exactly from the decimal\ndigits; the reader parses to f64 first and then tries to un-round it with\na tolerance-based continued fraction, so it loses at both ends of the\nrange. Past fixes (#79, #419, #604, #751) each landed in one copy only.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 1A FAIL markers at the filed issues\n\nThe disabled assertions were committed with placeholder markers before the\nissues existed. Each now names the issue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: declare (scheme inexact), unpin a non-conforming control\n\nTwo review findings on #1917, both valid, though the first for a different\nreason than stated.\n\nfinite?/infinite?/nan? are registered to (scheme inexact), so the import\nbelongs there. The claim that omitting it made the file fail was wrong --\nit ran 128 assertions green, because a top-level script reaches vm.globals\ndirectly whether or not the import is declared. That ambient reachability\nis exactly what kaappi#1831 documents, and relying on it in a test would\nhave made the file pass here while the same code failed inside a library\nbody. Declared explicitly.\n\nThe second finding was right outright, and investigating it found a bug the\ncontrol was hiding. Asserting (not (string->number ...)) pinned #f as the\ncorrect answer for a valid R7RS numeric string, so fixing string->number\nwould have looked like a regression. Rewritten to assert only the non-crash\nproperty. Probing why it returned #f showed the UNPREFIXED spelling of 2^63\nfails too, with the reader parsing it correctly -- the opposite parity from\nevery other divergence in this file. Filed as #1921 with four enabled\ncontrols and one disabled assertion.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:54+05:30",
          "tree_id": "86756ff19d7512557562d4326426a804332b910b",
          "url": "https://github.com/kaappi/kaappi/commit/2903f3532d14576629b5dcd949643a81aea2371d"
        },
        "date": 1785506432457,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.889947,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582048,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.028709,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004766,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047001,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057403,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.647567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23114,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.614311,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281133,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812327,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63892,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044207,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3",
          "message": "Make (srfi 14) a character set, not a multiset that stops at z (#1895) (#1928)\n\nThe library was three defects at once, and the third made the first two\nworse: `(char-set #\\a #\\a #\\b)` kept the duplicate, `char-set:full` was\ncode points 0-127 so `#\\λ` was not in it, and 23 of the SRFI's 64 names\nwere exported -- while `(cond-expand (srfi-14 ...))` answered yes, so\nportable code was told the library was there and then handed a multiset.\n\nA char set is now an inversion list: a sorted, disjoint, non-adjacent list\nof `(lo . hi)` code-point pairs. That is what makes it a set structurally\nrather than by filtering -- duplicates cannot be represented -- and what\nmakes `char-set:full` and `char-set-complement` two pairs instead of 1.1\nmillion list cells. `equal?` on two canonical range lists decides\n`char-set=` outright, which `char-set-hash` then rides on. All 64 spec\nnames are implemented; none is omitted.\n\nThe standard `char-set:*` constants come from generated Unicode general-\ncategory tables rather than from a scan over `(scheme char)`'s predicates.\nScanning was the obvious approach and two things ruled it out. It costs\n~0.14s per predicate, which is too much at every import; and making it\nlazy and memoised is unsafe in this engine, not merely inelegant. Globals\nare shared between SRFI-18 threads by pointer while heaps are per-thread,\nso a child thread forcing a memo writes a child-heap value into a\nparent-heap record, and the parent reads freed memory after the join.\nThat reproduces with no char sets involved -- a record box, `set!` from a\nchild, read from the main thread -- and a field holding a fixnum survives\nwhere one holding a fresh pair does not. So nothing here is ever mutated\nafter construction, and the tests pin that a constant read first from a\nchild thread is still sound in the parent.\n\nDeriving from categories is also what the SRFI asks for, but it means two\nvisible disagreements with `(scheme char)`, both intentional and both\ntested: `char-set:letter` is L* while `char-alphabetic?` answers for the\nbroader Alphabetic property, and `char-set:digit` is all 680 of Nd while\n`char-numeric?`'s hand-written 36-entry table covers only the 370 in the\nBMP. Each predicate is right for its own spec except the last, which is a\nseparate bug in `isUnicodeNumeric`.\n\nThe suite is written against the spec rather than the implementation: on\nthe pre-#1895 library it reports 17 passes and 144 failures. Beyond the\nspec's own worked examples it property-checks every range operation\nagainst a brute-force list-of-code-points model over a 121-character\nalphabet, which is what catches the overlap and adjacency cases hand-\nwritten tests reach only by luck -- four of five seeded mutations in the\nrange algebra are caught, the fifth being an equivalent mutant.\n\n`tools/gen_srfi115_charsets.py` becomes `tools/gen_srfi_charsets.py` with\na `--target {115,14}` selector, since it now feeds both libraries.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:58+05:30",
          "tree_id": "c194d0a1470722fc624ecafce71616e0468a0922",
          "url": "https://github.com/kaappi/kaappi/commit/3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3"
        },
        "date": 1785507139505,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.962166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.328717,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.835603,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044587,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.29722,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055244,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.298687,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158115,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510861,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.690756,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763706,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044462,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8cb776be89da98a9c82728d0f93c01d5e8eeffe5",
          "message": "Phase 1C: port refill sweep — 1714 configurations, a silent-split class, and a correction to #1893 (#1946)\n\n* Pin the reader's port-refill boundary with a token x offset sweep\n\n`(read port)` on an fd-backed port reads 4096-byte chunks and re-parses\nthe accumulated buffer after each one, treating only\n`ReadError.UnexpectedEof` as \"incomplete, read more\". A token straddling\na chunk boundary therefore survives only if its scanner happens to\nreport truncation with that exact error.\n\nSweeping 26 token kinds against every interior split point at both the\n4096 and 8192 boundaries -- against a string-port oracle over the same\nbytes, which cannot refill -- shows 12 kinds that do not, in two modes:\na hard `KP3000: read error` (strings, raw strings, `#u8\"...\"`, `#u8(`,\n`|sym\\x41;|`, and a multi-byte UTF-8 codepoint split anywhere, even\ninside a list) and a silent truncation with no error at all (bare\nsymbols, numbers, `#\\space`, `#\\x41`, `#true`, and line comments, whose\nremaining body is then read as program data).\n\nThe passing kinds are enabled and swept; the failing ones are commented\nout with a `;; FAIL:` marker. Fixtures are generated at run time and\ndeleted, so no 4 KB blobs are committed.\n\nWorth recording: #1893's own stated discriminating control -- \"the same\nfile with a bare symbol payload reads all 1024 datums\" -- does not hold.\nThe symbol only survived because it was wrapped in a list, which does\nrefill, and because the check counted datums instead of comparing them.\nAt top level the same symbol splits in two, silently.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point port-refill FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:42:38+05:30",
          "tree_id": "14d1054f4c209b7d0452ed420c561133b5d348ef",
          "url": "https://github.com/kaappi/kaappi/commit/8cb776be89da98a9c82728d0f93c01d5e8eeffe5"
        },
        "date": 1785508159081,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354779,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.93978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583787,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.979059,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004746,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047034,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318927,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057266,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.62904,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234423,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605772,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28174,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043638,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5dcf4e3776e00eae9b64a70f3cc550d528aa5646",
          "message": "Phase 4B: differential harness for the opt-off and cache tiers — 557 files, one real divergence (#1923)\n\n* Turn the execution-tier differential into a repeatable gate\n\nThe reconnaissance pass ran tiers (b) `--no-ir-opt` and (d) cold-vs-warm\n`.sbc` cache once, across 333 files, and found nothing. A one-off green\nrun is not a gate, and — for tier (b) — it was not even much of a\nnegative: only 3 of the 550 pre-existing corpus files make the IR\noptimiser do anything at all, because every `define`/`lambda` body lowers\nto an opaque `passthrough` node and the five passes only ever reach\ntop-level expression position. The other 547 compile identically with the\noptimiser off, so the comparison was vacuous for 99.5% of the corpus.\n\nSo the harness does three things the one-off sweep did not.\n\nIt measures its own vacuity. The summary reports how many files change IR\nunder `--no-ir-opt` and how many populated the bytecode cache (40 of 330\nby default; a program that imports is never cached), so a regression that\nsilently disables either shows up as a count collapsing rather than as a\nstill-green run.\n\nIt ships probes that the passes actually reach. `probes/` puts foldable,\ndead-branch, `not`-rewrite, identity and nested-`begin` shapes at top\nlevel, where the passes live, and leans on the cases where the rewrite is\nonly conditionally sound: `(if 0 ...)` is true in Scheme, `(* 1.5 0)` is\nnot `1.5`, and a shadowed `+`/`*`/`not` must suppress the rewrite\nentirely. Six of the seven are verified non-vacuous, tripling the number\nof corpus files that exercise the optimiser.\n\nIt decides nondeterminism by measurement instead of by a guessed skip\nlist. A tier mismatch has to survive three controls before it is\nreported: the file must actually be cached (otherwise cold and warm are\nthe same configuration, so a tier-(d) mismatch cannot be a cache effect),\ntwo cold baselines must agree, and the divergence must reproduce. The\nfirst control is what distinguishes a real finding from\n`nested-wait-under-sleep-dirty-snapshot-1490.scm`, which hung once under\nload and read as a cache divergence until the check was added. The static\nskip list is consequently empty.\n\nOne real divergence, found by the probes and suppressed via KNOWN_DIFFS\nso the suite stays green: on a cache HIT a runtime error loses its source\nline and snippet whenever the location comes from `Function.source_line`\nrather than the line table, because `vmErrorLocation`'s `fallback_line`\nis a hardcoded 0 on the cache-HIT path where the fresh-compile path\npasses the top-level datum's line. Exit code and stdout agree; only the\ndiagnostic degrades. `probes/cache-error-location.scm` carries the repro\nand its control side by side — `vector-ref` out of range, located by the\nline table, prints identically in both runs.\n\nUnlike the `;; FAIL: #1234` convention, that suppression cannot rot\nquietly: when a listed entry stops diverging the summary says so and asks\nfor it to be deleted. It is a note rather than a failure, because a gate\nthat goes red the moment someone fixes a bug teaches people to distrust\nit.\n\nWired into run-all.sh over the smoke+compliance+audit corpus plus the\nprobes: 330 files, 116s, inside the 300s shell-suite budget.\n`KAAPPI_DIFF_FULL=1` adds continuations/, hygiene/ and srfi/ — 557 files,\n210s — and is opt-in rather than the default because the extra 227 files\nbuy no additional tier coverage: zero of them change the IR, and they add\nseven cached files.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point the known cache divergence at kaappi#1922\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Reduce the differential corpus to probes/ on a Debug build\n\nCI's Debug leg killed the suite at run-all.sh's 300s SHELL_TIMEOUT. Debug\nruns the whole pipeline unoptimised and is ~500x slower on allocation-heavy\nwork, and the harness is ~1000 interpreter invocations, so the same sweep\nthat takes 110s on ReleaseSafe does not finish.\n\nReducing to probes/ rather than skipping the suite or raising the budget,\nbecause the census the harness itself reports says probes/ is where the\nsignal is: 9 of 331 corpus files make the optimiser do anything and 6 of\nthose 9 are the probes. Debug now runs 7 files in 15s and still covers 6 of\nthe 9 discriminating ones, so what it drops is the part that was vacuous by\nconstruction.\n\nDetected from {\"version\":\"0.22.0\",\"build_id\":\"ca18ae6\",\"target\":\"aarch64-macos-none\",\"build_mode\":\"ReleaseSafe\",\"gc_stress\":false,\"sandbox_available\":true,\"features\":[\"r7rs\",\"kaappi\",\"ieee-float\",\"exact-closed\",\"exact-complex\",\"kaappi-fibers\",\"kaappi-reactor\",\"kaappi-diagnostics\",\"posix\",\"kaappi-threads\"],\"srfis\":{\"builtin\":[1,9,13,18,39,69,133,170,192,254,258,260],\"portable\":[0,2,4,5,6,7,8,11,14,16,17,19,23,25,26,27,28,29,30,31,34,35,36,37,38,41,42,43,44,45,46,48,51,54,57,59,60,61,62,63,64,66,67,70,71,74,78,86,87,90,94,95,98,101,111,112,113,115,116,117,118,120,123,125,126,127,128,129,130,131,132,134,135,136,137,139,140,141,143,144,145,146,147,148,149,150,151,152,153,156,158,161,162,164,165,166,167,168,169,171,173,174,175,178,180,181,185,188,189,190,193,194,195,196,197,201,202,203,207,209,210,213,214,215,216,217,219,221,222,223,224,225,227,228,229,231,232,233,234,235,236,237,238,239,240,241,242,244,247,248,250,251,252,253,255,257,259,263,264,267,270,271]},\"limits\":{\"initial_frame_capacity\":480,\"initial_register_capacity\":2048,\"gc_initial_threshold\":8192}} rather than an env var, so it is\nright whether the build came from CI, a local -Doptimize=Debug, or a stale\nzig-out. KAAPPI_DIFF_FULL=1 still forces the whole corpus.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:39:36+05:30",
          "tree_id": "8976b3f277bc70b7a9d4ba341d32f72610c96978",
          "url": "https://github.com/kaappi/kaappi/commit/5dcf4e3776e00eae9b64a70f3cc550d528aa5646"
        },
        "date": 1785509657923,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973515,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.444874,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.842375,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004866,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044536,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297518,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.305599,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158962,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507275,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302923,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.777322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044957,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12",
          "message": "Phase 1B: delimiter sweep — 494 cells, 382 splits, and a guard that has never executed (#1931)\n\n* Sweep trailing-delimiter checking across every numeric prefix\n\nR7RS 7.1.1 requires a number to end at a <delimiter> or end of input.\n`Reader.readNumber` (src/reader.zig:366) enforces that, but only for\nun-prefixed decimals: `readNumberPrefixed` (src/reader_tokens.zig:481)\ncalls the unguarded `reader_tokens.*` functions directly, so any `#`\nprefix at all disables the check and one token silently reads as two\ndatums.\n\nThe systematic 19x26 sweep (19 prefix spellings x 26 trailing characters)\nsplits 382 of 494 cells; all 26 un-prefixed cells are correct, which is\nthe control axis. `string->number` rejects every failing cell, so each\ndisabled assertion is paired with an enabled oracle assertion. Chibi 0.12\nand Guile 3 raise on all of them too.\n\n148 assertions pass; 58 are disabled (55 under #1892, 3 under TBD for two\nnon-delimiter reader/string->number divergences the same sweep surfaced).\nThe enabled groups also pin the syntax a fix must not regress: SRFI 270\nhex floats, SRFI 169 digit separators, rationals, complex tails, and hex\n`e`/`d` as digits rather than exponent markers.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point delimiter FAIL markers at #1929\n\n#1892 reported the radix-prefix case; the sweep showed one bypassed call\nsite produces all 382 failing cells across every prefix spelling, so the\nmarkers name the wider issue that a fix will actually close.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:15+05:30",
          "tree_id": "f355651720339ada74bc4939f6ba72a5663ff21d",
          "url": "https://github.com/kaappi/kaappi/commit/cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12"
        },
        "date": 1785509664474,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358727,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.57382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.009405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047051,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319169,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057043,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636414,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230923,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61636,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276379,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.58907,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042981,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c5ddfe48acfbf8af321b798530fc53b24821b4bb",
          "message": "Phase 5C: cross-thread boundary audit — 49 assertions, six new findings including a read-direction UAF (#1938)\n\n* Map the cross-thread heap boundary, and pin the half of it that works\n\nPhase 5C of the v2 audit campaign. #1924 established that a child thread\nmutating a heap object reachable from a top-level binding leaves the parent\nreading freed memory. This maps how far that reaches, and — as importantly —\nwhere the boundary is actually sound, so those parts need not be re-audited.\n\n49 enabled assertions pin the working boundary: immediates (fixnum, char,\nboolean, flonum) survive every container; raw-byte content does too\n(string-set! including the widening rebuild, string-copy!, bytevector and\nf64vector elements); interned symbols survive because a child stamps them\nwith the parent's GC id; a child may store a parent-heap value into a\nparent-heap object and keep eq?; a child may grow a parent hash table across\na rehash; parameters are per-thread; a mutex left locked by a dead child\nreads as abandoned; join deep-copies results, nested objects included; and\nall seven reachable uncopyable tags are refused in both directions.\n\n24 assertions are commented out behind `;; FAIL:` markers rather than\ntest-expect-fail, because reading freed memory can take down the runner.\nSeventeen are #1924's shape across every mutable heap type — including the\nshared globals map itself and promise memoisation, which its own matrix\ndoes not cover. Seven are new and are marked TBD:\n\n  * the read direction, which #1924 does not cover: the parent's collector\n    reclaims an object a LIVE child still references, since markVMRoots\n    returns early unless vm.gc == gc. Under -Dgc-stress=true this escalates\n    to the engine's own UAF panic, 3/3, with the no-drop control clean 3/3.\n  * a plain R7RS record returned through thread-join! arrives as a\n    DIFFERENT record type: pt? answers #f and every accessor raises. The\n    supported worker-thread path, no globals and no mutation involved. A\n    SRFI 237 nongenerative type is the control and is enabled — its uid\n    registry is the one identity-preserving path in gc_deep_copy.\n  * gc_deep_copy's .channel arm skips the ownership check for an\n    already-promoted channel, so a grandchild that only ever reached a\n    channel through a shared global gets a working stub. The unpromoted\n    control is enabled and refuses.\n  * symbol interning is one level deep: at thread depth >= 2 a grandchild's\n    string->symbol no longer dedupes against the process table.\n  * a continuation invoked cross-thread returns a value satisfying no type\n    predicate at all.\n\nCLAUDE.md's claim that top-level bindings are shared by pointer while\nlexical captures are deep-copied-and-re-owned is confirmed, and both halves\nare now asserted directly.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point cross-thread FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:55+05:30",
          "tree_id": "4aa2be03e1a6302c71fd7fd1dfa0dfcaea17a740",
          "url": "https://github.com/kaappi/kaappi/commit/c5ddfe48acfbf8af321b798530fc53b24821b4bb"
        },
        "date": 1785510205407,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.335597,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.604451,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.450512,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.416965,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004082,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034737,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.230712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042794,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.831192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.896954,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172455,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237944,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.305979,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.440092,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035719,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "912b1e6246e05b822fe3968f982e614c1b8fe19a",
          "message": "Phase 2.2: primitives_io audit — 49 → 197 assertions, all 45 specs covered, one process-abort panic (#1947)\n\n* Phase 2.2: cover the 1100 lines primitives_io.zig grew after its audit\n\nThe audit test for src/primitives_io.zig was written against a version of\nthat file that predates custom ports, transcoded ports, the write-buffering\nlayer, and SRFI 192 — 112 lines of assertions against 1941 lines of code.\nThis takes it to 197 passing assertions covering all 45 spec entries, and\nleaves 8 disabled assertions marking defects the coverage found.\n\nFour defects, each paired with an enabled discriminating control so the\nmarker says *because of what*, not just *that it fails*:\n\n- A custom-port read! that re-enters a read on its own port trips\n  std.debug.assert(port.read_buf == null) and ABORTS the process — the\n  single-slot read buffer assumes no re-entrancy. Reachable at two sites\n  (readOneByteFromCustomPort, readOneByteFromTranscodedPort). Control: the\n  same shape returning one byte per call never populates read_buf and\n  completes cleanly. Its non-aborting sibling silently reorders the byte\n  stream.\n- SRFI 192's string-port branch ignores the port's own peek-byte read-ahead,\n  which the fd branch corrects for: port-position over-reports by one after\n  a pushed-back byte, and set-port-position! does not discard the stale byte,\n  so a seek is followed by a read of data from the old position. Controls:\n  the identical cases on a file port are both right.\n- port-has-set-port-position!? is registered to the same function as\n  port-has-port-position?, so it answers about get-position instead of\n  set-position! — wrong in both directions for a custom port with only one\n  of the two. Controls: ports with both, and with neither, answer correctly.\n- flush-output-port on a transcoded port is a silent no-op; it has custom-\n  backend and buffered-fd branches but no transcode branch, and a transcoded\n  port carries the fd -1 sentinel. Controls: flushing the wrapped port works,\n  and close-port does cascade.\n\nConfirmed correct along the way: the 8 KiB high-water drain and its\nflush/close/read triggers, fd-port positions corrected for read-ahead and\nwrite-behind, the freshly-re-read UTF-8 byte-offset conversion after a\nwidth-changing string-set! inside read!, CRLF decode and encode, both\ndecoding error modes, close-port's flush-and-cascade discipline, the\nblocking-callback rejection, and gc_deep_copy's refusal to carry a port\nacross a thread boundary.\n\nFound by: systematic audit v2, Phase 2.2 (docs/audit-strategy.md).\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point primitives_io FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:41:33+05:30",
          "tree_id": "dcf0c4b87487858c011e4a12cc7ad5a6041cbef6",
          "url": "https://github.com/kaappi/kaappi/commit/912b1e6246e05b822fe3968f982e614c1b8fe19a"
        },
        "date": 1785511043172,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.945213,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.399424,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.853622,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005031,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044442,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297564,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055146,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.299306,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157885,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510634,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.695136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760242,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044976,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6114398ba48db971cd17792170b82d92e3f439fd",
          "message": "Tick the eight units landed in the first two batches (#1948)\n\nThe tracker read 2 of 53 while eight units were merged, because each\nunit's PR added its test file without touching the tracker. The document\ncalls that tracker the single source of truth, so a stale one is the same\nfailure Phase 0B existed to fix: the next session to open it would have\nre-run work already done and re-filed issues already filed.\n\nEach entry records its PR and the issues it produced, so the tracker\nanswers what a unit found without needing eight PRs opened alongside it.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T20:49:37+05:30",
          "tree_id": "3994183ec5106eb2bdac9eda445056deddab5073",
          "url": "https://github.com/kaappi/kaappi/commit/6114398ba48db971cd17792170b82d92e3f439fd"
        },
        "date": 1785512696769,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.083364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.59766,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981369,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004997,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319096,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057249,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.645299,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231968,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619376,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284556,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815246,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648532,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043738,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "93fa575717d4339d84e008953104d530adc3b622",
          "message": "Stop a VM limit from arriving as a catchable condition (#1919)\n\nA recursive procedure that wraps its own recursive call in `guard` is\nordinary code, and past 64 levels it was silently incorrect: it returned\na plausible wrong value and exited 0.\n\nThe exception-handler and dynamic-wind stacks were fixed 64-entry inline\narrays. `with-exception-handler` relabelled the overflow as OutOfMemory\nand then converted it into an ordinary Scheme error object, so the\n*enclosing* guard caught it and its `(#t ...)` clause returned. A case\nthat must return 0 at every depth returned `(0 1 37)` for 63/64/100.\n`with-exception-handler` had it worse -- the overflow was invisible, the\nhandler simply receiving a bare `#<error \"error\">`.\n\nBoth stacks now grow on demand like the frame and register stacks\n(`-Dmax-handlers`/`-Dmax-winds`, hard cap 32768), and `errors.isUncatchable`\nkeeps VM limits and control-flow signals out of a user's `guard`: a limit\nof the implementation is not something the program raised, so it unwinds\nto the top level under its own code. `thread-terminate!` likewise no\nlonger runs the terminated thread's guard clauses on its way out.\n\nTwo error tags turned out to be overloaded, and only the suites said so.\n`OutOfMemory` is real exhaustion but equally the payload-size cap for\n`(make-vector 100000000000000)`, so it stays catchable. `StackOverflow`\ncovered `apply`'s 255-argument ceiling -- which is the bound that ends\nthe walk of a *circular* argument list, and has to stay recoverable --\nso those three sites become KP3007 with a message that names the real\nlimit, instead of sending readers to hunt for runaway recursion.\n\nFixes #1886\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:30:28Z",
          "tree_id": "6ad812fa1bd824b3379e7100f27d2705bd03360c",
          "url": "https://github.com/kaappi/kaappi/commit/93fa575717d4339d84e008953104d530adc3b622"
        },
        "date": 1785513593298,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.423656,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.619933,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.462667,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.548192,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005039,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04156,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.254491,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.048371,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.472071,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.039077,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.365679,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.271626,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.499003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.83458,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038942,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3de5281fede1fbbdb530005faa9bcc902479cc30",
          "message": "Phase 1D: printer audit — 79 assertions, five hangs, and a legal-but-wrong datum at depth 1023 (#1956)\n\n* Audit v2 Phase 1D: sweep the printer's structural round-trip\n\n`src/printer.zig` had no Scheme-level test of its own beyond a handful of\nZig unit tests.  Sweep it against the round-trip oracle -- (equal? x (read\n(open-input-string <written x>))) -- across every printable type and every\nstructural shape, with the four `write`-family contracts checked against\ntheir own R7RS 6.13.3 text rather than against each other.\n\n79 enabled assertions, 16 disabled.  Each disabled assertion is paired with\nan enabled control -- a near-identical input that behaves differently -- so\nthe file keeps proving the neighbouring path still works.\n\nBeyond the three symptoms already filed as #1902, the sweep separates that\nissue's single \"1024\" into three independent mechanisms with three distinct\ncliffs (markShared's cdr-spine depth; the seen[] cap, which makes detection\ndepend on an object's *position*; and the shared[] cap), and turns up five\nfindings it does not cover:\n\n- `write-simple` is registered as `.func = &write`, so it emits datum labels\n  on circular structure, which R7RS says it never may.\n- All four output procedures loop forever on a cycle reachable only through\n  a container the cycle pre-pass does not walk (error objects, mutex and\n  condition-variable names).  #1713 fixed this shape for record instances\n  and left the other arms behind.\n- An exact rational at nesting depth 1023 prints as \".../...\" and reads back\n  as a *symbol*: the printer's depth counter outruns the reader's nesting\n  count for that one arm, and the plain printer's truncation sentinel \"...\"\n  is itself a legal identifier.\n- `write-shared` becomes exponential once seen[] is full, so the same two\n  objects in a two-element vector print instantly one way round and never\n  terminate the other.\n- Closed issue #859 (REPL prettyPrint hang) still reproduces; the fix that\n  closed it removed the unbounded memory growth but not the hang, which now\n  lives in `exactFlatLen`.\n\nFindings only -- no printer changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point printer FAIL markers at the filed issues\n\nAlso drops the claim that #859 still reproduces. A properly constructed\npty test -- one that checks whether the REPL still services later input,\nrather than whether the process is merely alive -- shows it responding at\nboth COLUMNS=200 and COLUMNS=12, so that closed issue stays closed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:46:53+05:30",
          "tree_id": "1ec2247abc3ba02ae0a922b3488a7df7d6aea9c4",
          "url": "https://github.com/kaappi/kaappi/commit/3de5281fede1fbbdb530005faa9bcc902479cc30"
        },
        "date": 1785519951230,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302085,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.678265,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004664,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310848,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055927,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.61012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230189,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.55831,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280802,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.772434,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.5987,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045189,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3",
          "message": "Stop three diagnostics from misdescribing what they are about (#1958)\n\nEach of these sent a reader looking at the wrong thing.\n\nAn integral flonum rendered without its `.0`, so a type error on 1.0 read\n\"expected exact integer, got 1\" -- and 1 is an exact integer, so the message\nargued against itself. `safeValueDescription` formatted flonums with a bare\n`{d}` instead of the printer, so this affected every type error in the\ncodebase, not just the numeric-vector ones it was found in. It now goes\nthrough `printer.formatFlonum`, which is safe in this deliberately-defensive\nhelper: a flonum is inline under NaN-boxing, so nothing heap-shaped is read.\n\nA multi-limb bignum handed to a (srfi 160) constructor was reported as\n\"expected exact integer, got #<bignum>\". It is an exact integer; its only\nfault is not fitting s8..u64. `magnitudeAndSign` returned a plain `?MagSign`,\nwhich gave \"too wide\" and \"not an integer at all\" the same answer. Splitting\nthem into `ExactMag.too_wide` / `.not_exact` lets an out-of-range bignum say\n\"in-range\", matching what an out-of-range fixnum has always said -- and say\n\"non-negative\" instead when it is negative, since then the sign is the real\ncomplaint.\n\n`%record?` and `%transcoded-port` reported their errors as `record?` and\n`transcoded-port`. Those are not cosmetic truncations: both are real,\ndifferent procedures, exported by (srfi 237) and (srfi 181), with different\nargument lists -- `(record? 5 5)` is an arity error, not a type error. Both\nnow use the shared-constant convention primitives_srfi237.zig's MAKE_RTD\nalready documented for exactly this reason, so the name cannot drift again.\n\nThe audit that found these (#1890, Phase 2.1) had already written the\nassertions and commented them out as known failures; they are enabled here,\nalongside their original controls and three cases the audit did not cover\n(a negative multi-limb bignum, a signed-kind overflow, and a genuine\nnon-integer, which is what keeps \"in-range everywhere\" from passing). One\nof the four could not be enabled as written: `(not (has-substring? msg\n\"got 1\"))` cannot pass whatever the code does, since \"got 1\" is a prefix of\nthe correct \"got 1.0\" -- it is stated positively instead, which is fully\ndiscriminating because the buggy message was exactly \"got 1\".\n\nMutation-tested: reverting each of the three fixes in turn fails exactly the\nassertions belonging to it and no others.\n\nFixes #1916\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:47:11+05:30",
          "tree_id": "4e4667e4a449d0e129efd701cdcc4272bc647d0f",
          "url": "https://github.com/kaappi/kaappi/commit/1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3"
        },
        "date": 1785520126466,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.115725,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.261311,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.443981,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.183069,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004164,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035738,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.225216,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041166,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.147257,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.96069,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.211298,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.23357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281543,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.81746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04029,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "589aba141046e3b8544cf84787b4cb1b8a1579ad",
          "message": "Phase 2.4: SRFI 160 audit — 1066 assertions across 12 element kinds, one hang (#1952)\n\n* Phase 2.4: audit primitives_srfi160 across all 12 element kinds\n\nsrc/primitives_srfi160.zig is 280 lines and six %-prefixed generic\nprimitives, but those six are the entire native surface under 12 element\nkinds and ~732 exported names across 13 .sld files. It had no audit test,\nand the existing tests/scheme/srfi/srfi160.scm is 75% s8.\n\nAdds tests/scheme/audit/primitives_srfi160-audit.scm: 1066 assertions,\nevery 12-kind sweep generated from one kind table rather than written out\nper kind.\n\nConfirmed correct, systematically rather than by spot check: the 8\ninteger kinds at min/min+1/min-1/max/max-1/max+1 and against nine\ntype/exactness rejection classes; the two independent range checks\n(%uvec-elt-valid? in Scheme, expectSignedInRange/expectReal in Zig) agree\non a 12x23 corpus; f32 really truncates to single precision; -0.0, +-inf.0\nand NaN survive; c64/c128 pack two components independently and at the\nright width; a rejected set! never leaves a half-written element; the\nu8-as-bytevector seam holds in both directions; every per-type wrapper\nfixes its own kind symbol (12x12 predicate matrix plus every\nkind-constructing entry point); and callback errors propagate out of all\n18 higher-order generics, with an out-of-range callback result rejected\nrather than truncated.\n\nThree findings, disabled with a marker and an enabled control each:\n\n- Uvector-segment with n = 0 never terminates. %uvec-segment advances by\n  (min len (+ start n)), so start never moves while a fresh zero-length\n  copy is consed each iteration. All 12 kinds, both dispatch branches.\n  SRFI 160 makes n = 0 \"an error\", so a raise would conform; a hang does\n  not. Controls: n = -1 raises, n = 1 and n = 3 work, empty vector with\n  n = 0 returns ().\n\n- c64/c128 comparator hash raises on every value. %uvec-hash folds with\n  number-hash, which is (abs x)-based and rejects a complex. c64/c128\n  elements always decode to a Complex, so this fires even when every\n  imaginary part is zero. SRFI 160 requires the comparator to provide\n  hashing. Controls: the s8, f64 and u8 comparator hashes all work.\n\n- A zero-imaginary c64/c128 element writes as a form that reads back as a\n  different type: real? is #f, yet write emits \"1.5\", which reads as a\n  flonum. Affects the default fill, so every fresh c64/c128 vector has\n  such elements. Only decodeElement can produce them -- make-rectangular\n  normalises a zero imaginary part away. The vector printer prints\n  \"1.5+0.0i\" for the same bytes, so the two printer paths disagree.\n\nByte order is host-native by design and, on this evidence, not observable\nfrom Scheme: there is no NumericVector-to-bytes view, and NumericVector\nis not .sbc-serialisable. The printer and the primitives are two separate\nhand-written native-endian decoders, so the section 8 assertions use\nvalues whose byte-reverse is a different in-range number -- they assert\nencoder/decoder agreement rather than a little-endian layout, so they\npass on any host and would fail on s390x only if the two drifted apart.\n\nFound by: systematic audit v2, Phase 2.4\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI 160 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T23:11:25+05:30",
          "tree_id": "c2c96809d17d13065b03b09200c18c067ea72f26",
          "url": "https://github.com/kaappi/kaappi/commit/589aba141046e3b8544cf84787b4cb1b8a1579ad"
        },
        "date": 1785521556195,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.140581,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.408456,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.447896,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.214184,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004263,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036742,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228824,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041613,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.243518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.981944,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.252776,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.241359,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35194,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.763942,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034544,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e24e594ed8a650edb6b09d9216b16594a78610ad",
          "message": "Parallelise run-all.sh's shell suites, and stop rebuilding twice (#1957)\n\nThe shell suites were the larger half of run-all.sh's wall time and ran\nstrictly sequentially, because several scripts build into the one shared\nzig-out/ and would race each other's install. Two separate things had to\nchange: the race (which blocked concurrency) and the cost (which was\nsomewhere else entirely).\n\nThe cost was two full interpreter rebuilds. `zig build -Dbundle=…`\nrecompiles everything, since the embedded bytecode is part of the compiled\nmodule graph, and the two scripts that need a standalone binary each paid\nfor one — 85% of the shell suites' entire wall time for two tests. They\nneeded different embedded bytecode only because each carried its own\nfixture, so they now share one, in\ntests/scheme/compile/fixtures/bundle-replay/. Identical bytes make the\nsecond build a ~0.2s hit in Zig's own content-addressed cache. The .sbc is\nregenerated on every call rather than cached: unchanged sources give\nidentical bytes and the hit, while an edit under src/ changes them and\nforces exactly the rebuild it must — a cached .sbc of our own would go\nstale against the new binary's build id instead.\n\nThe race is closed at both ends. run-all.sh builds the runtime archive once\nup front and exports KAAPPI_RT_LIB_READY, which ensure_runtime_lib treats as\n\"already fresh\"; the marker is advisory, so a script run standalone (the\nWindows CI legs invoke each one directly) still builds its own. What builds\nremain take a mkdir-based lock — atomic on POSIX and Git Bash alike, where\nflock is Linux-only and macOS has none — and a lock whose holder was killed\nis stolen by the next waiter via the recorded pid. Six scripts had their own\ninline copy of the archive build, checking only for the file's existence;\nthey go through ensure_runtime_lib now, so one guard covers all 18.\n\nDispatch inside a suite is longest-first, found by grep rather than a list\nof names. Reporting still walks glob order, so a transcript diff between two\nruns stays meaningful at any job count.\n\nFull suite on a 12-core box: 475s -> 245s, same 2026 pass / 0 fail. The\nparallel and KAAPPI_TEST_JOBS=1 transcripts differ only in the line that\nreports the job count.\n\nCloses #1926",
          "timestamp": "2026-07-31T23:27:09+05:30",
          "tree_id": "a44f3a0ad9e71998d6a8746749f3433472bc0dba",
          "url": "https://github.com/kaappi/kaappi/commit/e24e594ed8a650edb6b09d9216b16594a78610ad"
        },
        "date": 1785523328128,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327595,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.23971,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.603549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.968196,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047056,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314084,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057826,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69526,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.222003,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.648019,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28591,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802526,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.679759,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043003,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db8e3d074fe64ead9d14b6b389d913e1a9dff132",
          "message": "Test what is inside each per-tag GC arm, not just that one exists (#1963)\n\nZig's exhaustiveness check guarantees markObjectContents, markValueInner,\nreferencesYoung, objectSize and freeObject each have an arm for all 41\nObjectTag members. Nothing guarantees the arm traces the tag's Value\nfields: one that forgets a field compiles cleanly and silently frees a\nlive object. Port's satellites are hand-written at five sites, and\nmarkValueInner deliberately duplicates markPortValues rather than calling\nit, so a third Value-bearing Port field would be invisible in up to five\nplaces at once.\n\nTwo runtime shapes, because the three mark-graph switches are reached by\ntwo different paths. Rooting a container makes markValueInner the only\nthing that can keep a referent alive. Promoting a container to the old\ngeneration, repointing a field through writeBarrier, then dropping the\nroot before a minor collection makes the remembered-set walk\n(markObjectContents, its only caller) the only route, and exposes\npruneRememberedSet's referencesYoung decision directly. Every rooted case\nends by dropping the root and asserting the referents die: an assertion\nthat cannot fail is not a test.\n\nLiveness is decided by walking the GC's own object lists for the\nreferent's address, never by dereferencing it -- reading back a swept\nreferent would be the use-after-free this file exists to detect.\n\nThe comptime inventory pins the exact field list of every heap struct\nthese switches dispatch on, plus the satellites they reach through\n(CustomBacking, TranscodeState, HashEntry, GuardEntry, WindRecord,\nExceptionHandler, SavedFrame, CallFrame). Value is u64, so no comptime\ntype test can tell a real Value from profile_calls -- pinning the whole\nlist is what makes the guard sound. Adding a field is now a build error\nnaming all five switches until someone has looked at them.\n\nMutation-tested: eight deliberate single-field deletions across\nmarkValueInner, markPortValues, referencesYoung and markFiberState each\nfailed exactly the intended case and nothing else, and a seventh Value\nfield on CustomBacking fails the build with the inventory error.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T00:04:40+05:30",
          "tree_id": "0b6e9a3003744e22473bbbb692aae9841479b758",
          "url": "https://github.com/kaappi/kaappi/commit/db8e3d074fe64ead9d14b6b389d913e1a9dff132"
        },
        "date": 1785526087883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.058264,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.199712,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.432448,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.27726,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003749,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229581,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042564,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.803694,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.898721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.181508,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239669,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.307003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.380815,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037203,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e58801829acda296b6fcddb1f86d945d9af05ff1",
          "message": "Stop piping into grep -q under pipefail (#1966)\n\n`grep -q` exits the moment it matches. When the match is on an early line\nof the output, the writer on the left of the pipe can still be mid-write\nand dies of SIGPIPE — and `set -o pipefail`, which every one of these\nscripts sets, then reports the whole pipeline as failed even though the\nmatch succeeded. The assertion fails while printing the very text it was\nlooking for.\n\nIt is a race, so it passes locally and on 16 of 17 CI legs, then fails on\nthe slowest one. #1957 made run-all.sh dispatch the shell suites\nconcurrently, which raised the load enough to fire it: three assertions in\ntests/scheme/errors/ failed on freebsd-test, each matching the first or\nsecond line of a multi-line output, each with the expected text visible in\nthe failure it printed. In every case the assertion beside it matching the\n*last* line passed, because grep then reads to EOF and the writer never\nsees a closed pipe.\n\nReproduced directly: with an early match and a large output, `echo \"$x\" |\ngrep -q PATTERN` under pipefail reports no-match 20 times out of 20, and\nthe here-string form 0 times out of 20. At the real ~3-line size it is\nabout 1 in 16,000 on an idle machine — rare enough to have gone unnoticed,\ncommon enough to bite three times in one run on an emulated 4-core VM.\n\nA here-string has no pipeline for pipefail to judge: same grep, same\npattern, same exit status, no second process whose death can be mistaken\nfor a failed match. Converted all 29 sites rather than the three that\nfailed, since they are one latent bug and the rest would surface next.\n\nTwo piped `grep -q` uses remain, in errors/reader-*-errors.sh: those have a\ncommand on the left rather than a variable, and neither script sets\npipefail, so neither can hit this.",
          "timestamp": "2026-08-01T01:18:44+05:30",
          "tree_id": "41a345cc698f8dd2d6924bd845d24699e9a8d1ad",
          "url": "https://github.com/kaappi/kaappi/commit/e58801829acda296b6fcddb1f86d945d9af05ff1"
        },
        "date": 1785529566020,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.959296,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.117832,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.595535,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.829967,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044767,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296501,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.504309,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16581,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.524644,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308806,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.687212,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817554,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044673,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db0533161a6b1294321bf611b13206ca6504472b",
          "message": "Tick the third batch, and mark 5B as landed-but-blocked (#1968)\n\n1D, 2.4 and 7B are merged. 5B is ticked as complete work with its PR\nstill open, because it is blocked by a CI regression on main (#1967)\nrather than by anything in the unit -- leaving it unticked would imply\nthe work is outstanding when what is outstanding is someone else's\nFreeBSD failure.\n\nEach entry records what the unit found AND what it confirmed correct.\nThe two units that found no bugs in their target are the ones most at\nrisk of being read as wasted, so their entries say what they closed:\nnine untested false rows in the unwind asymmetry, and a 41-tag mark\ngraph whose arm contents nothing could check.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:00:15+05:30",
          "tree_id": "10d24394df48e68650b6ebf4b7772864a79c6d27",
          "url": "https://github.com/kaappi/kaappi/commit/db0533161a6b1294321bf611b13206ca6504472b"
        },
        "date": 1785533974500,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961673,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.607652,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557629,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834074,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004867,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044936,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295251,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059248,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.510185,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15452,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.764885,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783166,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045887,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2b2027b1d8c95e9e7932da541ad37edc2af9da14",
          "message": "Phase 5B: waitForFd park-vs-drive — 26 tests for a protocol that had zero direct coverage (#1960)\n\n* Assert which branch waitForFd took, not just that the read worked\n\n`waitForFd`, `driving_waits` and `anyAncestorWaitResolved` had zero direct\nreferences in any src/tests_*.zig. The park-vs-drive branch was reached only\nincidentally, through Scheme programs that happened to block, and incidental\ncoverage cannot say which branch ran: a change that made every caller drive in\nplace — or every caller park — would have left the whole suite green.\n\nsrc/tests_waitforfd.zig (26 tests) asserts the branch. The selector,\n`my_idx != 0 and vm.dispatched_from_scheduler`, is plain VM state, so all four\ncells are set up directly rather than raced into; the two that must DRIVE are\ndiscriminating controls for the two terms of the conjunction. The park cells\nuse an fd that is already readable, which separates \"parks because it was told\nto\" from \"parks because the fd was not ready\".\n\nThree gaps this closes beyond the branch itself:\n\n- The #1625 unwind asymmetry. `IoWait` is the only wait kind setting\n  `unwind_on_resolved_ancestor`, and runSchedulerStep gates on `@hasDecl`, so\n  opting a join/channel/mutex/condvar wait in — or IoWait out — compiles\n  cleanly and silently changes blocking semantics. A comptime table over all\n  ten production Ctx types pins it; the nine `false` rows had no coverage at\n  all. `anyAncestorWaitResolved` gets direct tests for its identity filter,\n  its timed_out disjunct, and its whole-stack scan.\n\n- The yield-retry contract. A parked primitive re-executes from scratch, so\n  progress in a Zig local is lost. Five tests reach a *confirmed* park with the\n  stream torn mid-item (mid-UTF-8, mid-line, mid-CRLF, mid-datum) and assert\n  both that the prefix landed in port.read_buf and that the resumed primitive\n  produces the whole item, plus a control at an item boundary where nothing\n  may be stashed. The write side takes the other route — drain before append,\n  progress in write_buf_start — and is checked for loss and duplication.\n\n- Which frames actually force the drive branch. `guard` does; `map` and\n  `dynamic-wind` do not, because both are bootstrapped in Scheme\n  (vm_bootstrap.zig) and their thunk call stays in the same runUntil. All\n  four fibers in that test run the identical `(read-char rp)`. README section\n  Fibers already says this; two Zig doc comments still name dynamic-wind and\n  map/for-each as re-entrant native frames, including the user-visible\n  \"port I/O abandoned\" message text.\n\nDeterminism, rather than sleeping, comes from FIFO dispatch: a trivial\n`(fiber-join (spawn ...))` dispatches every already-spawned fiber to its first\nblocking point first. 6/6 identical runs; unchanged under -Dgc-stress=true.\n\nThe production diff is visibility only — nine wait-context types go `pub` so\nthe asymmetry table can name them — plus the vm_tests.zig registration.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Gate the write-side parking assertions to POSIX\n\nWindows CI reached .completed where the test expected .io_waiting: the\n20 KB write is accepted outright, so the flush never EAGAINs and there is\nnothing to park on. Shrinking SO_SNDBUF is what forces the park on\nkqueue/epoll hosts and it does not have that effect there.\n\nWhy the mechanism is not stated in the comment: I could not establish\nwhether the reduced SO_SNDBUF is ignored or the socket layer simply\nbuffers past it, and this cannot be checked from the dev machine. The\ncomment records the observed outcome and says so, rather than asserting a\ncause that was never verified.\n\nThe gate covers only the three parking assertions. The lossless-resume\nassertions -- 20000 bytes arriving exactly once, nothing lost to a park\nand nothing duplicated by a re-execution -- are the property the test\nexists for, and they still run on every platform whether or not a park\noccurred.\n\nVerified: 30/30 on macOS with the gate in place (so it does not silently\ndisable the test here), and `zig build test -Dtarget=x86_64-windows`\ncompiles clean -- the same command CI's windows-cross job runs.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:13:39+05:30",
          "tree_id": "d08a5fccaf4ff34f7ba9e8882d7536c6c8f468dd",
          "url": "https://github.com/kaappi/kaappi/commit/2b2027b1d8c95e9e7932da541ad37edc2af9da14"
        },
        "date": 1785536810385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.24768,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.674911,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.45735,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.24858,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004612,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.24723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.045303,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.279681,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.015743,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.262393,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.254601,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.833433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03751,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3",
          "message": "Say which kind of failure a port error is (#1944) (#1969)\n\nprimitives_io.zig had 44 typeError sites and zero indexError/argError\nsites, so every non-type failure in the file arrived mislabelled.\n\nSeeking a string port past its end raised a detail-less \"invalid\nargument in 'set-port-position!'\" — no index, no length — while the\nsibling non-seekable path three branches down did set detail. It reports\nindex and length now (KP3006).\n\nwrite-string's range check blamed args[0]: `(write-string \"abc\" p 5)`\nsaid \"expected valid range, got #<string>\", naming the one argument that\nwas valid. The offending index is named now, following substring, the\nhouse precedent for a start/end pair. An inverted-but-in-range pair is\nneither a type nor a range fault, so `(write-string \"abc\" p 2 1)` is\nargError: \"start 2 is greater than end 1\".\n\nA closed port was \"type error: expected open input port, got #<port>\".\nA closed port is a port, and the direction check has already run, so\nnothing about its type is wrong — that is argError (KP3007). A genuine\nnon-port, and an input port where an output port is wanted, are still\ntype errors; both are pinned as controls.\n\nThree internal guards carried the tag .claude/rules/gc-safety.md\nforbids: waitPortFd and raisePortClosedDuringIo reported a missing VM or\nGC as KP3007, blaming the program for a broken interpreter. #1874\nblessed these as Rule 1 keepers on the grounds that they \"already\ncarried a tag of their own\" — but InvalidArgument is not a tag either\nfunction returns for any other reason, and raisePortClosedDuringIo is a\nbyte-for-byte twin of raiseWrappedPortClosed 950 lines down the same\nfile, which Rule 2 had already moved. Both are settled the same way now,\nand the doc's seam paragraph says why the Rule 1 side is narrower than\nit read.\n\nThe audit file's existing assertions only ever asked whether a bad call\nraises, which is how all of this drifted; 13 new assertions pin the\nmessage text, 9 of which fail without this change. The guard tags are\nunreachable from Scheme, so they get a Zig test where the private\nhelpers live.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:25:15+05:30",
          "tree_id": "3d6c4b566c2864f447d18282ec13a6ece5c07ca8",
          "url": "https://github.com/kaappi/kaappi/commit/9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3"
        },
        "date": 1785536944840,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.785897,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.952305,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31136,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056612,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.686396,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.24324,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582693,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.771485,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.50433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042888,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "49699333+dependabot[bot]@users.noreply.github.com",
            "name": "dependabot[bot]",
            "username": "dependabot[bot]"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fab1e9e9864d8b9b0caf98df3609801924cefe37",
          "message": "Bump vmactions/netbsd-vm from 1.4.3 to 1.4.4 in the github-actions group (#1970)\n\nBumps the github-actions group with 1 update: [vmactions/netbsd-vm](https://github.com/vmactions/netbsd-vm).\n\n\nUpdates `vmactions/netbsd-vm` from 1.4.3 to 1.4.4\n- [Release notes](https://github.com/vmactions/netbsd-vm/releases)\n- [Commits](https://github.com/vmactions/netbsd-vm/compare/fac0a63f3e5244c600cb9ca532d27ee774ecdb4b...bf34bcd909bb50856f934a67d09a8fbe2b966a1b)\n\n---\nupdated-dependencies:\n- dependency-name: vmactions/netbsd-vm\n  dependency-version: 1.4.4\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-01T02:31:30+05:30",
          "tree_id": "0e04d110683f4745caedbdc00e29ef9edc2bcc65",
          "url": "https://github.com/kaappi/kaappi/commit/fab1e9e9864d8b9b0caf98df3609801924cefe37"
        },
        "date": 1785537513088,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.927184,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.157308,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560264,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.816146,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045731,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054657,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.31871,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157812,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577712,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.296566,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.675182,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765222,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044383,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "775890947add3c041dcaa46606f654797330ec9f",
          "message": "Document what may actually cross a thread boundary (#1964)\n\nThe uncopyable-tag list in gc_deep_copy.zig reads as the authoritative\nanswer to \"what can cross a thread boundary\". It is not: it governs the\n*copy* route only — the thread-start! thunk closure, the thread-join!\nresult, a channel message. A value reached through the shared globals map\n(VM.initForThread shares the parent's map by pointer) is never copied and\nnever reaches that switch.\n\nThirteen of the fourteen tags are freely usable through a top-level\ndefine, and for mutexes and condition variables a global is the *only*\nsupported way to share one — exactly inverted from a channel, which must\nbe captured lexically. Nothing anywhere noted that the two differ, and\nthey appear side by side in every concurrency example.\n\nThe globals route is defended per-type inside individual primitives, and\ntwo types do so: channels and thread handles. Extending that to the rest\nuniformly is not possible — it would remove the sole way to synchronise\nthreads — so the honest model is documented instead, with the two\nknown-unsound rows left to their own issues (#1924, #1936).\n\nCLAUDE.md's \"threads cannot share mutable heap state\" was the false\nguarantee in its most compact form; it now describes both routes.\n\ndocs/dev/thread-value-sharing.md holds the per-type matrix.\nsrfi18-sharing-model.scm pins both routes for the nine types covering\nevery distinct enforcement shape, as a characterisation test, so a change\nto any row fails visibly instead of widening the gap silently.\n\nCloses #1937\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T21:10:49Z",
          "tree_id": "d2444d938a890c0924bc2a6909420c9b4f7d7cae",
          "url": "https://github.com/kaappi/kaappi/commit/775890947add3c041dcaa46606f654797330ec9f"
        },
        "date": 1785539453227,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.272862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.045469,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580243,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.954901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004639,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056273,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.677575,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230175,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571281,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282839,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.767409,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611099,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044674,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea2e2e4988014e8fdcd40e9a0e1d957a96366918",
          "message": "Stop the \"port I/O abandoned\" error naming dynamic-wind as unparkable (#1965)\n\nThe message named \"guard, dynamic-wind, callbacks\" as frames a fiber cannot\nsuspend under. dynamic-wind is bootstrapped Scheme: its body runs in the\nbytecode dispatch loop and a fiber parks inside it like a bare read, so the\nerror sent users to move blocking I/O out of a dynamic-wind for no reason and\nleave it inside the guard that actually caused the drive.\n\nIt now names what genuinely opens a nested native frame: guard, and the native\nhigher-order drivers (SRFI-1 fold/filter/find, hash-table-walk, assoc/member\nwith a custom predicate, string-index, eval).\n\nSix comment copies of the same misclassification are corrected alongside,\nincluding raiseDeadNativeReturn's \"(map, for-each, sort, apply, ...)\", which\nnames sort — portable Scheme in lib/srfi/95.sld. README's list dropped sort\nfor the same reason.\n\nRegression test: readers blocking inside dynamic-wind, a map callback, and a\nsort comparator must all reach .io_waiting when dispatched before any writer\nexists, contrasted with the adjacent #1625 test where guard drives.\n\nCloses #1959",
          "timestamp": "2026-08-01T03:18:44+05:30",
          "tree_id": "bfe137901e3db835719f43581031bc920923d102",
          "url": "https://github.com/kaappi/kaappi/commit/ea2e2e4988014e8fdcd40e9a0e1d957a96366918"
        },
        "date": 1785539635941,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.254348,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.736404,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.596318,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.947722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004738,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04658,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31624,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057427,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69308,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160761,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587188,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284167,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.775336,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640932,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044048,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ab961376f282c00a307028ea6aa09994bee2f311",
          "message": "Drop the resolved blocker from the 5B entry (#1971)\n\n#1960 merged, so \"open, blocked by #1967\" is no longer true in either the\nstatus line or the unit entry. #1967 was the pipefail/grep -q race in the\nshell suites, fixed by #1966; 5B's FreeBSD leg then passed with nothing\nchanged but its base.\n\nLeft alone deliberately: the entry still records that 5B found no bugs in\nwaitForFd and says what it closed instead. That is the part most likely to\nbe misread as a wasted unit, and it is the reason the entry is worth\nhaving.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T03:29:54+05:30",
          "tree_id": "833a0f07a416b0052c538d54bc36536d5875124f",
          "url": "https://github.com/kaappi/kaappi/commit/ab961376f282c00a307028ea6aa09994bee2f311"
        },
        "date": 1785539745203,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.261632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.641274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.60754,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.949783,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005107,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316313,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057629,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.723387,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.205618,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.606921,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290104,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793277,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685328,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044872,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5fdc06de60ce50a6e0b7efb163cfa185cf0e5445",
          "message": "Phase 2.5: SRFI 237 audit — 186 assertions, and a 27-field record aborts the process (#1975)\n\n* Audit primitives_srfi237.zig: 186 assertions, one uncatchable panic\n\nPhase 2.5 of the v2 audit campaign (docs/audit-strategy.md, #1890). The\nfile had no audit test and postdates the v1 campaign entirely.\n\nCovers all 18 specs, the R6RS `define-record-type` desugarer that shares\ntheir enforcement helpers, and the portable layer in lib/srfi/237.sld\nthat is their only other caller. The oracle is R6RS Library chapter 6:\nSRFI 237 defines every one of these as \"equivalent to the procedure with\nthe same name in R6RS\", so R6RS's own sentences are quoted beside the\nassertions they justify.\n\nConfirmed correct, with the assertions to keep it that way:\n\n  * Protocol composition over a 4-level chain, all 16 present/absent\n    combinations, plus the rule that a protocol runs once per\n    record-constructor call and never per instance.\n  * Field shadowing — a child redeclaring an ancestor's field name gets\n    its own slot, its own mutability, and leaves the ancestor's readable.\n  * sealed, enforced identically from both layers via one shared helper.\n  * nongenerative uid reuse, and all four R6RS equivalence axes rejected\n    with the differing axis named. The type NAME is correctly not an axis.\n  * A nongenerative record survives thread-join! with its identity, by\n    uid re-resolution in gc_deep_copy.\n  * All 18 arities match their bodies; all 18 reject bad input catchably.\n\nDisabled, each paired with an enabled control (26 markers):\n\n  * A record type with 27 or more fields PANICS on instantiation —\n    allocRecordInstance sizes itself in u8 arithmetic. Uncatchable, and\n    reachable from plain R7RS define-record-type, not just SRFI 237.\n    Control: 26 fields works.\n  * record-type-field-names returns a list; R6RS requires a vector.\n  * record-accessor/record-mutator take k as an absolute index across\n    inherited fields; R6RS requires an own-field index. Control: the\n    by-name path resolves per level correctly, and record-field-mutable?\n    already uses own-field indexing on the same rtd.\n  * The opaque flag is stored but never enforced: record? answers #t,\n    record-rtd returns the rtd, and opacity is not inherited.\n  * record-mutator does not reject an immutable field.\n  * Three specified names are absent and undocumented: the 7-argument\n    make-record-descriptor, make-record-constructor-descriptor, and\n    record-constructor-descriptor?.\n\nAlso pins the current behaviour of #1914 (own-field 255-limit overflow\nreports a bare TypeError blaming args[0] while the inherited path reports\nit precisely), #1915 (constructor arity unchecked, so an extra argument\nsilently shifts the field layout) and #1932, so their fixes flip a test.\n\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI 237 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T03:36:47+05:30",
          "tree_id": "820e20c4c901e51210b7a60b1232818cdf755dc3",
          "url": "https://github.com/kaappi/kaappi/commit/5fdc06de60ce50a6e0b7efb163cfa185cf0e5445"
        },
        "date": 1785540559899,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.270532,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.122883,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.606205,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.950425,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004715,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04682,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315995,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057198,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.719247,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.205352,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611071,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2911,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.784604,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698868,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044987,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c3e05be76342221dc8c933c78d5c00ddd2504a6e",
          "message": "Phase 6D: LSP end-to-end — 152 assertions for a 942-line server with no prior integration test (#1987)\n\n* Audit 6D: drive the language server end-to-end, 152 assertions\n\nkaappi_lsp.zig was 942 lines with 6 inline unit tests and no integration\ntest of any kind — the largest wholly-untested subsystem in the tree. It\nneeds no editor to test: it is JSON-RPC over stdio with Content-Length\nframing, so a shell driver can write framed requests to the real binary's\nstdin and assert on the framed replies.\n\ntests/scheme/lsp/lsp.sh pins the advertised capability set, exact framing\n(a lone shutdown is exactly 60 bytes on the wire), id correlation, a full\ninitialize -> initialized -> didOpen -> hover/definition/references/\ndocumentSymbol/completion -> shutdown -> exit session, and cross-checks\nevery published diagnostic against `kaappi check --diagnostics=json`,\nwhich shares the serializer in src/lsp_diagnostic.zig.\n\nCross-checking is where the value is. On read and compile errors the two\nsurfaces agree exactly on code, severity and start line. They diverge in\nfour ways, all reproduced with a discriminating control and left as\ndisabled assertions:\n\n  * a `define-syntax` in one open document leaks through the shared\n    vm.macros table into every other document's diagnostics, so\n    byte-identical text is diagnosed clean and then KP2001 purely\n    because an unrelated file was opened; closing it does not retract\n    the macros, and a plain `define` of the same name does not leak.\n  * `hasMore() catch false` discards every reader error raised while\n    skipping intertoken space, so an unterminated `#|` comment hides\n    the whole file — no diagnostic and an empty documentSymbol list —\n    while check reports KP1001.\n  * runDiagnostics breaks at the first bad form, so a two-error file\n    publishes one diagnostic where check reports two; and no KP4xxx\n    lint runs at all, so check's arity error exits 1 on a file the\n    editor shows as clean.\n  * the range is always a whole-line 0..999 sentinel, never the real\n    span check pinpoints.\n\nProtocol edges account for the rest: a malformed *body* is skipped and\nthe session continues, but a malformed *header* silently ends it and\ndrops every later message; a request whose params are missing gets no\nreply at all, so a client blocks on that id forever; shutdown is answered\nbefore initialize and requests are still served after it; exit without a\nprior shutdown returns 0 where LSP requires 1; and a column past\nend-of-line resolves a symbol on a later line.\n\nNo hangs found. Deeply nested input, recursive macros, prose, and\nunopened URIs all degrade cleanly. Runtime 3.4s, deterministic over 5\nruns. Discovery only — no server code changed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point LSP FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T04:12:23+05:30",
          "tree_id": "303ce149ce4fb5fe469b145f4bb3d4ce26d7b6a5",
          "url": "https://github.com/kaappi/kaappi/commit/c3e05be76342221dc8c933c78d5c00ddd2504a6e"
        },
        "date": 1785540837603,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.184053,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.125663,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.275183,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.513863,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.002861,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.02383,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.145922,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.02752,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.243178,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.586527,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.810014,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.19347,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.883137,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.189009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025018,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e7c723ddf073ad0865ba358f129607c3c0916c77",
          "message": "Tick 2.5 and 6D; close 3.2/3.3 as subsumed by 2.4 (#1990)\n\n* Close SRFI 160 sweeps 3.2 and 3.3 as subsumed by 2.4\n\n2.4 audited primitives_srfi160.zig AND the portable surface it carries,\nwhich is what 3.2 and 3.3 were scoped to cover separately. Its 1066\nassertions already sweep all 12 element kinds at every boundary, both\nseams, and the per-type wrappers.\n\nLeft open, they would tell the next session that SRFI 160 coverage is\nmissing when it is not -- the same class of drift Phase 0B existed to\nremove, just pointing the other way: a tracker that overstates remaining\nwork wastes a session as surely as one that understates finished work.\n\nStruck through rather than deleted, with what 2.4 actually covered\nrecorded inline, so the decision is auditable instead of looking like\nunits that quietly vanished.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.5 and 6D, and record why 2.12 and 5D are not ticked\n\nOnly two of the fourth batch merged. 2.12 and 5D are complete and green\non macOS but held by real BSD failures -- 2 assertions on FreeBSD and\nOpenBSD, 1 on NetBSD, out of 421 and 273 respectively.\n\nThose stay unticked rather than ticked-with-a-caveat, because the work is\nnot landed and the tests are not running anywhere. The status line names\ntheir PRs so the next reader knows the units exist and where they stopped,\ninstead of finding two silently missing entries.\n\nUnlike the earlier #1967 case, this is not harness flake: the failures are\nin the units' own audit files, on the platforms whose filesystem and\nthread semantics those units probe, and the same files pass everywhere\nelse. Chasing them needs a real BSD box.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T04:50:56+05:30",
          "tree_id": "126dd8c90836116d52c13be556bf97b05954044d",
          "url": "https://github.com/kaappi/kaappi/commit/e7c723ddf073ad0865ba358f129607c3c0916c77"
        },
        "date": 1785541364331,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.254822,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.863211,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.588007,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.951469,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00471,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046534,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315574,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057158,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.645479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.228194,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581629,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28531,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.780013,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648735,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043476,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c1fb2025bcd90d0cd64991376ba714e91ca822ff",
          "message": "Phase 5D: SRFI-18 re-audit — 77 → 274 assertions, and thread-terminate! cannot interrupt a native wait (#1986)\n\n* Phase 5D: re-audit SRFI-18 — 274 assertions, six bugs, one of them a hang\n\nThe v1 campaign audited src/primitives_srfi18.zig at 994 lines. It is now\n1435 lines across 34 specs (+793/-352 over 27 commits since the v1 base),\nwhile tests/scheme/audit/primitives_srfi18-audit.scm had not changed since\n2026-07-10. This grows it from 77 assertions to 274 (+197), covering every\nspec — thread-yield! had never been called at all — plus the full mutex\nstate matrix, the condition-variable protocol, the terminate matrix, and\ntime/timeout parsing in both spellings.\n\nSix root causes found, all with a discriminating control, 20 assertions\ndisabled behind `;; FAIL:` markers:\n\n* mutex-unlock! never clears the abandoned flag, so an abandoned mutex a\n  program explicitly resets by unlocking still raises a spurious\n  abandoned-mutex-exception. SRFI 18: \"Unlocks the mutex by making it\n  unlocked/not-abandoned.\"\n* thread-terminate! on an already-terminated thread destroys its\n  end-result (and, for a thread that raised, its end-exception): the\n  `terminated` store sits above its own completed/errored guard, and\n  threadJoinResult tests `terminated` first.\n* thread-terminate! is not observed by a thread parked inside a native\n  SRFI-18 wait. #880 was closed by a 1024-instruction dispatch-loop\n  safepoint, which a thread blocked in threadSleepFn / mutexLockFn /\n  mutexUnlockFn's condvar branch never reaches. thread-join! then blocks\n  for the rest of the wait — or forever, when the wait is untimed.\n* Unguarded float-to-int conversions abort the process (exit 134,\n  uncatchable) in seconds->time, thread-sleep!, and timeoutToDeadlineNs —\n  the last of which also serves mutex-lock!, thread-join!, mutex-unlock!\n  and (kaappi fibers) channel timeouts. Two distinct panics, one cliff.\n* mutex-lock! with a terminated thread as the owner argument records it as\n  the owner instead of making the mutex unlocked/abandoned.\n* A thread that terminates itself joins as an uncaught-exception with a\n  void reason rather than a terminated-thread-exception.\n\nThe suite is deterministic and bounded: no wall-clock assertions, every\nwait either timeout-bounded or resolved by a thread the file joins, and\nevery aborting or hanging shape commented out rather than\ntest-expect-fail'd. Helper threads spin in Scheme rather than sleeping —\nterminating a sleep-polling child costs 3.8s against run-all.sh's 60s\nper-file timeout, because terminate latency tracks wall-clock time per\n1024 bytecode instructions.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI-18 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Stop pinning the value of an undefined float conversion\n\nCI's NetBSD failed \"seconds->time +nan.0 collapses to 0\". That assertion\npinned the result of @intFromFloat on a NaN, which is undefined -- macOS\nand the NetBSD reference VM both happen to yield 0.0, so it passed\neverywhere I could reach and failed where I could not.\n\nSix sequential runs and twelve four-way-concurrent runs on the NetBSD VM\nwere all clean, which is exactly why the CI log had to be read for the\nassertion NAME rather than the failure re-created: an idle box cannot\ndistinguish \"fixed\" from \"did not fire\", and this was never a race to\nbegin with.\n\nThe finding the assertion exists for is that NaN does NOT abort, unlike\n+inf.0 and |x| >= 2^63 which do (#1983). That contrast survives without\nnaming a value, so it now asserts only that a time object comes back.\n\nVerified on the NetBSD VM: 274 pass, 0 fail.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T06:24:25+05:30",
          "tree_id": "9ba57b12ca70152f2d2bf1e0aa27fc7312f4baac",
          "url": "https://github.com/kaappi/kaappi/commit/c1fb2025bcd90d0cd64991376ba714e91ca822ff"
        },
        "date": 1785548739422,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.269905,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.015683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.607222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987249,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004703,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04667,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057145,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.696756,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.204723,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589758,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287722,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785645,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.610294,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043337,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "321da93a6fd8ab5ef64c637ac0338894e4cae1c1",
          "message": "Evaluate guard clauses in the guard's own dynamic environment (#1991)\n\nFixes #1988.\n\nR7RS 4.2.7 evaluates a guard's implicit `cond` \"with the continuation and\ndynamic environment of the guard expression\". A handler, though, runs at the\nraise point, with every `parameterize`/`dynamic-wind` extent entered since the\nguard still live — and the desugaring handed the escape continuation the cond's\n*value*, so the clauses ran there. A plain `raise` hid it, because this VM\nunwinds before calling any handler; the `raise-continuable` a declining `guard`\nissues for its implicit re-raise does not, so an extent between a declining\ninner guard and an outer one leaked into the outer guard's clauses.\n\nThe clauses now run after a new internal `%unwind-to-escape` has left those\nextents. Escaping to the continuation first would do the same job in one step —\nthe issue's own suggestion, and what R7RS's sample implementation does — but the\nescape has to come after the clauses, not before: a clause may reinstate a\ncontinuation captured inside the guard body, and this VM cannot resume one whose\nnative frame has returned. `(srfi 255)`'s restarters are exactly that shape, and\nescaping first breaks them. Splitting the unwind from the escape keeps those\nframes standing; the escape then finds the wind stack already at its target.\n\nOne deviation remains, documented under \"Known limitations → Exceptions\" in\nREADME.md: with no matching clause the re-raise happens in the guard's dynamic\nenvironment rather than the original raise's, which is what a plain `raise`\nalready does here.\n\nAlso fixes a pre-existing leak on the same path: `raiseContinuable` re-pushed\nthe handler it had popped even when the handler left via a continuation that had\nalready reset the handler stack. `guard`'s handler always leaves that way, so\nevery declining guard stranded one slot — 32768 hit the KP3008 cap.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)",
          "timestamp": "2026-08-01T06:43:36+05:30",
          "tree_id": "7786e4f016b4ca6ddd2638d2871bc5688c2c3a16",
          "url": "https://github.com/kaappi/kaappi/commit/321da93a6fd8ab5ef64c637ac0338894e4cae1c1"
        },
        "date": 1785549153528,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.446467,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.655736,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.587069,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.013796,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005032,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048615,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319843,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058708,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.766632,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.255872,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.643694,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301625,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822337,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724247,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048961,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "793abc6a9999beb324f424307b8e7e83606e5c67",
          "message": "Make SRFI 237's record procedures obey R6RS 6.3 (#1989)\n\n* Make SRFI 237's record procedures obey R6RS 6.3\n\nSRFI 237 defines most of its procedural and inspection layers as\n\"equivalent to the procedure with the same name in R6RS\", and four of\nthem were not. Each had a control in the same library showing the data\nneeded was already present, so these were reporting bugs rather than\nmissing capability:\n\n  - record-type-field-names returned a list where R6RS requires a\n    vector, while make-record-type-descriptor already demanded a vector\n    for the same field list.\n  - An integer k for record-accessor/record-mutator indexed the whole\n    instance rather than the rtd's own fields (\"k cannot be used to\n    specify a field of any type rtd extends\"), so it silently returned\n    an ancestor's field -- and disagreed with record-field-mutable?,\n    whose own k was already own-relative. The integer path also skipped\n    rtd validation and never range-checked k.\n  - The opaque flag was stored and read back but never enforced, and\n    was not inherited from an opaque parent.\n  - record-mutator returned a working mutator for an immutable field.\n\nKeeping %record-type-field-names list-valued and converting at the\npublic boundary leaves the primitive's contract, its audit test, and\nthe internal index walks in SRFI 57/131/136/150 untouched. Opacity is\nmade effective at construction by a helper both creation paths share,\nfor the same reason the sealed-parent and nongenerative rejections\nalready share theirs: the procedural and syntactic paths must not drift\ninto disagreeing about what R6RS requires.\n\nSRFI 137 relied on the absolute-index reading -- its subtypes declare\nzero own fields, so no k names the payload -- and now asks by name.\n\nAlso add the three specified names that were missing, which made a test\nwritten against the R6RS spelling fail on the binding rather than on the\nbehaviour under test: make-record-constructor-descriptor,\nrecord-constructor-descriptor?, and the 7-argument\nmake-record-descriptor.\n\nThe 7-argument form is specified as passing its `parent` to both\nmake-record-type-descriptor and the parent-descriptor slot, which only\ntype-checks once a record descriptor is accepted wherever an rtd is\nexpected -- the SRFI's \"the type of record descriptors is a subtype of\nthe type of record-type descriptors\". That widening exposed the\nremaining gap: a syntactic define-record-type's <record name> evaluates\nto a simple rtd, and a protocol lives on the descriptor, so deriving a\nprotocol-less descriptor from one would quietly bypass the protocol and\nstore the raw constructor arguments. Rather than give RecordType a\nGC-traced protocol field, %record-type-constructor recovers the\nfinished, protocol-applied constructor the desugarer already bound,\nafter confirming the sibling type alias still names that same rtd (both\naliases are keyed by type name, so a generative redefinition rebinds\nthem). When it cannot be recovered and the new has_protocol bool says\nthere is one, it raises rather than building a wrong record. Together\nthese make the SRFI's own worked Examples section run -- a procedural\ntype inheriting from a syntactic one whose construction a protocol\ngoverns.\n\nFixes #1974\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Note the SRFI 237 conformance fixes in the changelog\n\nrecord-type-field-names changing from a list to a vector is a breaking\nchange for any caller, so it needs the migration note rather than just\na bug-fix line.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Re-pin the SRFI 237 audit to the corrected R6RS semantics\n\n#1975 landed its audit while this fix was in review, so the two disagree\nby construction: 20 of its assertions pinned the defects #1974 reports as\na \"before\" for exactly this PR, and 10 more sat commented out waiting for\nthe fix. Flip both sets.\n\nThree of the re-pinned ones needed a real rewrite rather than an edited\nexpectation, because they read an inherited field by index -- which is\nprecisely what R6RS says k cannot do. The 4-level protocol matrix and the\narity cases now reach each level's single field as k=0 on that level's\nown rtd, walking the parent chain, so they exercise the same instance\nslots without relying on the flat layout.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T06:45:42+05:30",
          "tree_id": "0ddf8334f627640311beb339dc3338386bb14fa3",
          "url": "https://github.com/kaappi/kaappi/commit/793abc6a9999beb324f424307b8e7e83606e5c67"
        },
        "date": 1785549796008,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.90522,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.830477,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5563,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.933475,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004794,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044731,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291311,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054475,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.338485,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.146848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.509085,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309517,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.665579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.775094,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045192,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e6081c3ba6db8aa8b00526fd71c5fb8d00354216",
          "message": "Tick 5D, and record the portability lesson it cost (#1992)\n\n5D merged with all three BSD legs green. 2.12 remains blocked: the rdev\nfix was real and verified on the FreeBSD VM, but CI then surfaced a\nsecond, distinct divergence that the VM cannot reproduce -- CI runs\nFreeBSD 14.3 and the reference VM runs 15.1, and their assertion totals\ndiffer (423 vs 412), so the two are not comparable runs.\n\nThe 5D entry records the lesson rather than just the issue numbers,\nbecause it generalises: an assertion that pins the VALUE of an undefined\nfloat conversion passes everywhere the conversion happens to agree and\nfails where it does not. Assert the property that is actually specified --\nhere, that NaN does not abort, which is the real contrast with #1983's\naborting cases.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T07:43:03+05:30",
          "tree_id": "5c4782daabbc524c1ada38770730747e6c944467",
          "url": "https://github.com/kaappi/kaappi/commit/e6081c3ba6db8aa8b00526fd71c5fb8d00354216"
        },
        "date": 1785551790540,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.916267,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.703441,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.554643,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.808193,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004849,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044966,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291276,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054778,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.329555,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.147941,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.515761,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307842,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.674297,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.76172,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044506,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0ea592b34aa98c74a1e827c36b0635820dfdc70",
          "message": "Phase 2.12: filesystem audit — 69 → 428 assertions, and file-info aborts on any /dev path (#1985)\n\n* Audit primitives_filesystem.zig: 69 -> 428 assertions, all 68 specs\n\nv2 audit campaign Phase 2.12 (docs/audit-strategy.md).  The file had 68\nregistered procedures and ~102 syscall sites against a 177-line test that\nnever mentioned 10 of them, and exercised almost no error path.\n\nAdds the syscall-boundary matrix the happy-path tests never reach —\nnonexistent path, wrong kind of object in both directions, permission\ndenied, broken symlink, symlink loop (including a self-loop), path too\nlong, empty path, embedded NUL across all 24 path-taking procedures,\nrelative-vs-absolute, and a path that vanishes between two calls — plus\nfile-info across every reachable file type, the full directory-object\nlifecycle (read past end, double close, use after close, mutation during\ntraversal, 2000-entry buffer refill, GC finalisation of an unclosed\nstream), the error taxonomy, and the SRFI-18 deep-copy boundary.\n\nEvery disabled assertion carries a \";; FAIL: TBD\" note and an enabled\ncontrol proving the same validation fires for a neighbouring input, so\nthe gap is located rather than merely observed.\n\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point filesystem FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Stop asserting one platform's spelling of \"no device number\"\n\nFreeBSD reports st_rdev = -1 (NODEV) for a non-device file where macOS\nand Linux report 0, so three assertions that hardcoded 0 failed there --\n2 in CI, 3 when run directly on the FreeBSD reference VM.\n\nWhat the SRFI actually promises is that a plain file has no device\nnumber, not what the absent-value sentinel looks like, so accept either\nspelling and say why in a comment.\n\nFirst attempt used (test-equal #t (memv ...)), which still failed:\nmemv returns the matched tail, not #t. Converted to test-assert.\n\nVerified on the FreeBSD VM: 409 pass / 3 fail before, 412 pass / 0 fail\nafter.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Name every assertion in the filesystem audit\n\nCI's freebsd-test fails two assertions in this file and the log prints\nbare `#f` / `FAIL` with nothing to identify them. The reference VM runs\nFreeBSD 15.1 against CI's 14.3 and executes 11 fewer assertions, so the\nfailure cannot be reproduced locally -- leaving no way to tell WHICH\nassertions fail.\n\nBy contrast the NetBSD failure in 5D was diagnosed in a single step,\nbecause that assertion happened to have a name: the CI log printed\n\"FAIL TODAY: seconds->time +nan.0 collapses to 0\" and pointed straight\nat it.\n\nNames are derived from the expression under test rather than invented,\nso they stay meaningful and need no upkeep: (test-equal 0 (file-info:rdev\nfi)) becomes (test-equal \"(file-info:rdev fi)\" 0 (file-info:rdev fi)).\n\nSRFI-64 already supports source-file/source-line, but nothing populates\nthem -- portable syntax-rules cannot capture source location -- so naming\nis the only route available in Scheme.\n\nSemantics-preserving, verified: 426 assertions before and after, 428\npasses before and after, and test-name now appears in the log. An earlier\ncut of the generator truncated labels BEFORE escaping them, which sliced\n`#\\z` to `#\\` and produced an invalid escape; it now truncates first and\nescapes after, so a trailing lone backslash is legal.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix three platform assumptions the BSD legs caught\n\nNaming the assertions (previous commit) paid off immediately: freebsd-test\nprinted `FAIL (memv (file-info:rdev fi) '(0 -1))` instead of a bare `#f`,\nwhich named the defect outright.\n\nrdev: POSIX defines st_rdev only for character- and block-special files.\nFor everything else it is unspecified, and two successive guesses were both\nwrong on CI — first 0 (macOS, Linux), then {0, -1} adding FreeBSD's NODEV.\nFreeBSD 14.3 still failed for a regular file while *passing* for a fifo in\nthe same run, which is precisely what \"unspecified\" licenses. Dropped both\nvalue assertions; the exact-integer? check is the whole portable contract.\n\nfd exhaustion (#1993): the suite opened 3000 directory streams without\nclosing them, asserting the GC reclaimed them. It does — but only when its\nallocation-count threshold happens to trip, never on descriptor pressure.\nAt `ulimit -n 256` exactly 253 unclosed opens succeed, i.e. no collection\nruns at all; at 1024, 1745 do. Ports behave identically (253 / 1747), so\nthis is a property of every fd-holding object, not of open-directory. The\nassertion passed on macOS and Linux only because their limit is 1048576,\nand on openbsd-test and netbsd-test it exhausted the table and took down\nthe *next* block, which could no longer create its own scratch files:\n\n    error[KP3000]: cannot open output file \"/tmp/kaappi-a212-68521-14/f0\"\n\nDisabled behind a FAIL marker, and replaced with the half the program\nactually controls: 3000 open/close cycles must not accumulate descriptors.\n\nLog noise: three stray `#f` lines came from this suite's own top-level\ncleanup calls, because kaappi echoes non-void top-level values when running\na script. That is deliberate and long-standing, but documented only in\ndocs/dev/fuzzing.md — filed as #1994. Here the fix is local: an empty\ncond-expand else branch and void-returning cleanup helpers.\n\nVerified at ulimit -n 256, 512, 1024 and the default: 427 passes, 0\nfailures, and two lines of output.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T08:25:34+05:30",
          "tree_id": "380a94de94a16a7b89614c7704875c9653d9213d",
          "url": "https://github.com/kaappi/kaappi/commit/d0ea592b34aa98c74a1e827c36b0635820dfdc70"
        },
        "date": 1785557594009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.395255,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.50684,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.603686,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.993736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00475,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046961,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313045,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057365,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.620513,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.226148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587602,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286927,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786872,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.475363,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044115,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1aedd4014ee6a3ddc5b3fc88a20b81db5f0e2228",
          "message": "Phase 2.3: SRFI 181 audit — 196 assertions, and (read port) has never worked on a custom or transcoded port (#2015)\n\n* Phase 2.3: audit SRFI 181 custom and transcoded ports\n\nprimitives_srfi181.zig had no audit test at all. This adds one — 196\nassertions plus 17 disabled — covering all 10 native specs, the whole\nportable layer in lib/srfi/181.sld, and the SRFI's own obligations on the\nimplementation that nothing else asks about: the read!/write! argument\ncontract, the six callback sites' blocking rejection, positioning under\nlookahead, cross-heap deep copy, and the eol-style x error-mode matrix in\nboth directions.\n\nFive issues filed, none fixed here (the campaign separates discovery from\nfixing):\n\n  #1995  (read port) returns #<eof> on every custom and transcoded port —\n         readDatumFn is the one input primitive that goes around\n         readOneByte, so it never invokes read! at all. read-char,\n         read-line, read-string and read-bytevector on the same port all\n         work; a string port and a file port read the same datum fine.\n  #1996  port-position on a custom port returns get-position verbatim,\n         ignoring the port's own read-ahead. The fd path subtracts it one\n         branch below. Also breaks the spec's explicit \"must return its\n         cached position rather than calling get-position\" after a peek.\n  #1997  Transcoded output ignores #\\return as a line ending, so a crlf\n         transcoder writes CR CR LF for one CRLF and a round trip turns\n         one line break into two. The decode direction gets it right,\n         which is what makes this an internal inconsistency.\n  #1998  close-input-port closes the output side of a bidirectional\n         custom port too, and runs its close callback.\n  #2012  Not SRFI 181's: the first (environment '(srfi N)) on a\n         file-backed .sld silently abandons the rest of the enclosing\n         top-level form. Found because a probe in this suite looked like\n         it passed and had in fact never run.\n\nClean results worth recording: the blocking-callback guard is correct at\nall six callback sites and every rejection stays catchable; the eol-style\ndecode matrix is right in all nine cells, including the lf-on-input case\nnothing tested before; gc_deep_copy refuses custom and transcoded ports\ncleanly at both SRFI-18 boundaries; and every neighbouring re-entrant\ncallback shape completes, which localises #1939 to the single-slot\nread_buf rather than re-entrancy as such.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point 2.3's tracker entry at the PR that actually exists\n\nThe entry cited #1999, written before the PR was opened. The PR is #2015;\n#1999 is not a pull request at all.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:11+05:30",
          "tree_id": "9355b4384f90d4864a87085c321de02745688913",
          "url": "https://github.com/kaappi/kaappi/commit/1aedd4014ee6a3ddc5b3fc88a20b81db5f0e2228"
        },
        "date": 1785560865965,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.383034,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.277644,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57284,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.989605,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312584,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05709,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.568376,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234059,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.576814,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27986,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794835,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.598625,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04322,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b94afc2bd917c568a69b9737e818eb6f6996d437",
          "message": "Phase 2.6: fibers audit — 32 → 111 assertions, and a channel receive inside a custom-port callback aborts the process (#2004)\n\n* Phase 2.6: audit (kaappi fibers) — 32 → 111 assertions\n\nprimitives_fiber.zig grew +1241/-110 since the v1 campaign against a\n135-line audit test — the largest churn-to-coverage ratio in the\nprimitives table. All 11 specs are covered now, along with KEP-0002 §6\n(capacity, rendezvous, close!, timeouts), the KEP-0001 park-vs-drive\nprotocol, and both halves of the cross-thread sharing model.\n\nFour findings, nine assertions disabled behind their issue numbers:\n\n- #1999 spawn never binds the thunk's parameters, so a non-thunk runs\n  anyway with the fiber's own closure and #<undefined> as arguments\n- #2000 channel/fiber blocking inside a SRFI-181 custom-port callback\n  bypasses in_custom_port_callback and aborts the process (SIGBUS)\n- #2001 fiber-join has no Object.owner check, so a child thread joins a\n  parent-heap fiber and gets the parent's object uncopied\n- #2002 argument diagnostics misidentify the problem\n\nEvery assertion carries a name string, and nothing asserts wall-clock\ntiming — only relative ordering and bounded termination — since this\nsuite runs under emulation on several CI targets.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.6 in the audit tracker\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:48+05:30",
          "tree_id": "5c841c3136d66ed2cc824666068b359703ada988",
          "url": "https://github.com/kaappi/kaappi/commit/b94afc2bd917c568a69b9737e818eb6f6996d437"
        },
        "date": 1785561313471,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.386274,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.305795,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.585689,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.99437,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004971,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04665,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312631,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057241,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.590334,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.227978,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.603996,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284607,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.789558,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.689255,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044194,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "940368ca69d1b97be0e12a274e7409351819c359",
          "message": "Phase 2.11: six unaudited primitives files — 247 assertions, and a use-site (let ((car ...))) hijacks car inside any macro (#2014)\n\n* Phase 2.11: audit the six unaudited small primitives files\n\nparallel, sysinfo, random_port, srfi258, srfi260 and srfi211 — ~570\nlines and 27 specs, all postdating the v1 campaign, none with an audit\ntest. 230 SRFI-64 assertions plus a 17-assertion --sandbox suite for\ndimension D7.\n\nThe six files are clean. All 27 specs behave correctly, every %-name is\nreachable with no import (D1) and none panics, the --sandbox gate matches\nits documented per-name split exactly, and SRFI 258's uninterned-ness\nsurvives both deep-copy directions with object sharing preserved.\n\nEvery finding is in the surrounding engine, reached through these files'\nown documented claims:\n\n  #2003  a use-site local binding captures a macro template's free\n         reference to a global procedure, so (let ((car ...)) ...)\n         hijacks car inside any macro. The local-scope half of closed\n         #1812; syntax-rules and ER alike, wrong against Chibi and Guile.\n  #2005  load of a file containing import fails, blaming the loader's\n         own line 1.\n  #2007  kaappi check calls two valid SRFI 211 transformer-specs\n         invalid syntax.\n  #2009  doc-truth: SRFI 260's rationale still says Kaappi has no\n         uninterned symbols, 51 minutes after SRFI 258 gave it some.\n\nExtended #1913: the all-zero-seed port's own state fails\nrandom-port-state?, so it cannot be rebuilt from itself.\n\nSeven assertions are staged disabled behind #2003 and #1913. The\nhygiene section keeps its parity assertions enabled, so a fix that\nlands on only one of the two macro paths fails here.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point the 2.11 tracker entry at the real PR number\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:52+05:30",
          "tree_id": "054c2f0d6a87030b8b47945ccfde25d0931fbff4",
          "url": "https://github.com/kaappi/kaappi/commit/940368ca69d1b97be0e12a274e7409351819c359"
        },
        "date": 1785561811859,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.079073,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.245033,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.456125,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.200223,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004234,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035077,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.230393,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042727,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.860285,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.90167,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.187181,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24118,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.353094,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.442884,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036042,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "abb036b44e4cd61b5447944b5a8852deb69030ae",
          "message": "Phase 2.10: SRFI 254 audit — 178 assertions, and a guardian shared through a global kills the process with no message at all (#2013)\n\n* Audit SRFI 254: 178 assertions for a GC-integrated file with no test\n\nPhase 2.10 of the v2 audit campaign (#1890). primitives_srfi254.zig is the\nonly primitives file with real garbage-collector integration and had no audit\ntest at all, so the surface covered here spans four files: the 16 specs, the\nweak-reference fixpoint in gc_collect.processWeakRefs, guardian invocation in\nvm_calls.invokeGuardian, and the deep-copy refusal arms in gc_deep_copy.zig.\n\nThe ephemeron half is correct, including the parts a weak pair gets wrong: a\ntwo-link chain resolves consistently in both directions, and an ephemeron\nwhose value references its key -- or whose key *is* its value -- still breaks.\nAll 16 error paths carry the right KP code, every call-dispatch site accepts a\nguardian, and all three weak types fail cleanly across both SRFI-18\nboundaries.\n\nThree defects, all filed rather than fixed, per the campaign protocol:\n\n  #2008  invokeGuardian has no owner check, so a guardian shared through a\n         global -- which the thread sharing model shares by pointer -- is\n         mutated across heaps. Concurrent registration aborts the process\n         with empty stdout and stderr, 5 of 5. Channels and thread handles\n         both defend themselves this way; guardians do not.\n  #2006  Transport cell keys are held strongly, against the spec's \"stored in\n         a weakly holding location\". Cells never break and no registration is\n         ever releasable -- observable because it also stops an unrelated\n         object guardian from resurrecting the same object.\n  #2011  A second guardian watching one object never resurrects it: the first\n         guardian's ready queue is marked strongly, so every other guardian's\n         reachability probe sees a live object. Thirty collections do not\n         help; draining the winner unblocks it immediately.\n\nNothing asserts when a collection happens, only what is observable after one\nis forced. The suite is green in ReleaseSafe (0.09s) and under\n-Dgc-stress=true (16s).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Hold both operands live in two hash/eq? assertions\n\nAn object freed between the two current-hash calls can be replaced at the\nsame address, which would make equal hashes correct rather than a collision;\nand an ephemeron whose key is dropped immediately breaks, so the eq?-identity\nmiss would pass for the wrong reason. Both now bind their keys.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the disabled-assertion count in the tracker (5, not 4)\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T10:55:22+05:30",
          "tree_id": "1919aeed2d1ceeb71f353f882442fe8e1dac04a0",
          "url": "https://github.com/kaappi/kaappi/commit/abb036b44e4cd61b5447944b5a8852deb69030ae"
        },
        "date": 1785563852038,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391479,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.562978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.588991,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.001321,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00479,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046536,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313201,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057432,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.605899,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225157,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592895,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284812,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793924,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.673317,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044553,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0d03deb89134671c0b279efb70e254cddd30978",
          "message": "Stop reporting a platform and a range rule as type errors (#2016)\n\nFive typeError sites in primitives_io.zig put a non-type in the \"expected\ntype\" slot: four `comptime is_wasm` gates said \"expected non-WASM platform,\ngot #<string>\", and fd->port rejected 0 with \"expected socket/pipe file\ndescriptor (> 2)\" — but 0 is a fixnum, exactly the type it wants.\n\nFor the three (scheme file) procedures this was not only cosmetic. R7RS 6.13\nsays they signal a condition satisfying file-error?, which is what they do on\nevery native target and what portable code guards on, so the type error fell\nstraight through such a guard on the WASM tier — the playground. They now\nraise through raiseFileError, the same helper their own native failure path\ntwo lines down already used, with the platform named in the message and the\npath still the irritant. fd->port has no spec and no file, so its gate and\nboth range rules are argError (KP3007).\n\nA comptime gate cannot be tested from a native build, so\ntests/wasm/platform-gates.scm covers those four under wasmtime in the `wasm`\nCI job; fd->port's native range rules join #1944's text assertions in the io\naudit. Both sets were mutation-tested against the reverted source.\n\nCloses #1972\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T11:13:51+05:30",
          "tree_id": "6fdbf071b1541a34b825ceafa21d0c4d26c072c6",
          "url": "https://github.com/kaappi/kaappi/commit/d0d03deb89134671c0b279efb70e254cddd30978"
        },
        "date": 1785564714098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.929649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.282882,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.532599,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.72361,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004821,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043845,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.274473,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053547,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.78424,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.087951,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.427751,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.261189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.628944,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.891383,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041955,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "50fa0f2da37df7e58297fa03cbe34b809af87b1e",
          "message": "Tick 2.12, reconcile the batch count, and record three footguns (#2017)\n\nFive units landed together (#1985, #2004, #2013, #2014, #2015), taking the\ncampaign to 22 of 53. Each unit ticked its own box; this reconciles the\nstatus line, which four of them raced on, and ticks 2.12, whose PR carried\nonly the test file.\n\nThe three footguns are what 2.12 paid for. It needed three CI rounds and\nnot one of them was a defect in the code under test:\n\n- Name every assertion. SRFI-64 prints a failed assertion's value, not its\n  source, so an unnamed failure on a remote BSD leg is `#f` / `FAIL` with\n  nothing to identify it among 400. The round after names went in, the log\n  read `FAIL (memv (file-info:rdev fi) '(0 -1))` and named the defect.\n- Never assert a value the spec leaves unspecified. POSIX defines st_rdev\n  only for character- and block-special files; two guesses were both wrong,\n  and FreeBSD 14.3 failed for a regular file while passing for a fifo in\n  the same run.\n- A test's side effects must not be platform-scaled either, and\n  `( ulimit -n 256; ... )` is the cheapest BSD-leg simulator available.\n\nThat last one also corrects a finding. 2.12 reported \"3000 unclosed\ndirectory streams do not exhaust the fd table\" as confirmed-correct; it is\na false clean, true only at macOS and Linux CI's ulimit of 1048576. At 256,\n`--gc-stats` reports Collections: 0 and exactly 253 opens succeed. That is\nnow #1993, alongside #1994, and the entry says so rather than repeating the\nclaim.",
          "timestamp": "2026-08-01T11:25:08+05:30",
          "tree_id": "c92205b39fd178636c86390bd008e75d53f8d827",
          "url": "https://github.com/kaappi/kaappi/commit/50fa0f2da37df7e58297fa03cbe34b809af87b1e"
        },
        "date": 1785565417114,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34943,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.783095,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.990335,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004603,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047032,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314862,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057081,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.697569,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.214074,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276672,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790047,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.607832,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044301,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a66a85cc689ed2c29e050bd29be9cc5b7af6cc29",
          "message": "Document the issue-tracker label taxonomy and priority rubric (#2032)\n\nThe four priority labels carry one-line GitHub descriptions that are too\ncoarse to settle real triage, so the working rubric existed only as\nprecedent spread across ~1000 issues. Labeling a new issue meant reading\nits neighbours and inferring the rule, which is fine for a maintainer who\nfiled those neighbours and useless to everyone else.\n\nRecords the rule adopted today — `critical` is reserved for process-level\nunsafety, and a correctness bug tops out at `high` however broad or silent\nit is. This is not invented: 11 of the 12 issues ever labeled critical are\nmemory unsafety or a process abort, and the twelfth (#1250) is called out\nas a pre-rule exception so nobody calibrates against it.\n\nAlso captures the two distinctions the precedent encodes but never states:\nreachability separates critical from high (#1939 aborts from five lines and\nis critical; #2000 is the same abort class but needs ~2500 fibers and is\nhigh), and an audit header's severity is an input to the priority decision\nrather than the answer, since `wrong-result` spans high to medium purely on\nblast radius.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T11:54:29+05:30",
          "tree_id": "54919109d67526e4135bcb2734600c417ae43580",
          "url": "https://github.com/kaappi/kaappi/commit/a66a85cc689ed2c29e050bd29be9cc5b7af6cc29"
        },
        "date": 1785569450453,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.44251,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.332419,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.489069,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.408022,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004834,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041235,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.256969,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.047529,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.390818,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.038192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.368223,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276819,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.486866,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.913231,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039169,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "08828884cdbbc3529a373c39f3b5b3405f6bc46a",
          "message": "Phase 2.13: error taxonomy and diagnostic fidelity — 98 assertions, and the bare-return path CI forbids produces a better message than the one it enforces (#2029)\n\n* Phase 2.13: audit the error taxonomy and diagnostic fidelity\n\nCross-cutting sweep over all 31 primitives_*.zig files plus src/ffi.zig,\nagainst the codebase's own written contract: docs/dev/adding-features.md's\ntypeError/indexError/argError table and the explanation text that\n`kaappi explain` prints for KP3002/KP3006/KP3007.\n\n98 assertions on the code and the message content, never on `raises?` alone\n-- that is the documented lesson from #1944 and the central hazard of this\nunit. 64 further assertions are disabled behind `;; FAIL:` markers; each was\nverified to fail when enabled and to pass nowhere else.\n\nFour issues filed:\n\n  #2020  33 bounds failures report KP3002 instead of KP3006. The largest\n         contributor is parseOptionalRange, shared by 20 procedures.\n         `substring` and `string-copy` are the same operation by R7RS\n         definition and return different codes.\n  #2021  72 sites reject a correctly-typed value as KP3002 rather than\n         KP3007, because the type branch and the range branch of one check\n         share a single message string.\n  #2022  31 procedures misreport which procedure failed: shared helpers\n         hardcode 'string' (a real, working procedure), 'arithmetic', and\n         'string operation'.\n  #2026  CI's bare-TypeError gate misses src/ffi.zig on both axes at once --\n         wrong path glob and wrong spelling -- so 27 bare returns there have\n         never been reported.\n\n#1899 (F10) was extended rather than re-filed. Its stated rationale for the\nopacity does not hold: mapNativeError runs the full allocating printer on the\nsame error path, so `(sqrt 'the-key)` names the symbol while\n`(magnitude 'the-key)` reports `#<symbol>`. The suite pins that pair.\n\n13 of 31 primitives files are clean on both taxonomy axes and are asserted as\nsuch, along with the codes that are already granular -- KP3001/3003/3004/3005\neach stay distinct from KP3002.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.13, and record what the taxonomy sweep found\n\nCites PR #2029 and the four issues it filed. Deliberately does not touch the\nStatus count line -- the orchestrator reconciles that.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T13:07:42+05:30",
          "tree_id": "b684d75f680ac976f646d387f1e7fdeffe92a84a",
          "url": "https://github.com/kaappi/kaappi/commit/08828884cdbbc3529a373c39f3b5b3405f6bc46a"
        },
        "date": 1785576573261,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.961075,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.346625,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.424688,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.103577,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004223,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03522,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.226383,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040699,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.079597,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.916972,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.189519,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.287636,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.734572,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034903,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "400aef3c3f3279786347d4c438d4d7f6e2a8ea20",
          "message": "Correct #1250's label and drop the critical-corpus exception (#2041)\n\n#2032 merged five minutes before this content reached the remote, so it\nshipped the first commit only. Everything below was written against that\nbranch and is landing now; main currently says #1250 is the critical\ncorpus's standing exception while the tracker has it labeled high, which is\nthe kind of contradiction this document exists to prevent.\n\n#1250 was the one issue labeled `priority: critical` that the rule did not\ndescribe: a macro-introduced `set!` escaping assignment conversion, which is\na pure correctness bug with no memory unsafety. Both of its reproductions\nhang, and a hang is `high` here — #1954, where four output procedures hang\nforever on a cycle, is the direct precedent. Relabeled, so all 13 issues\never marked critical are now memory unsafety or a process abort and the rule\nis fully descriptive. The doc keeps the correction rather than quietly\ndropping the issue: a lone counter-example in the corpus is exactly what a\nfuture maintainer would calibrate against.\n\nThree other fixes the same pass turned up. The critical table was already\nstale — #2027 and #2024 were labeled after it was written — so it now lists\nall 13. The claim that doc-truth is \"reliably low, because by construction\nthe behaviour is correct\" has a live counter-example in #2038, where the\nundocumented caveat hides a loop running 2^n-1 times that past n≈20 prints\nnothing and exits 0; the premise is now something the reader is told to\ncheck rather than assume. And the invariant gains its one real exemption:\nauto-filed `fuzz-finding` CI reports are triage-and-close, and all six ever\nfiled were handled with no priority label, so the triage query skips them\nrather than reporting a gap that nobody intends to close.\n\nAlso replaces the total-issue count with a claim that does not rot, since\nthe audit campaign files in bursts and the number moved twice while the\noriginal branch was open.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T13:12:12+05:30",
          "tree_id": "af1ea9de7f4b5fcd5f4fd58d53a07d2205d89747",
          "url": "https://github.com/kaappi/kaappi/commit/400aef3c3f3279786347d4c438d4d7f6e2a8ea20"
        },
        "date": 1785581006832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.384146,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.819936,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570632,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.992623,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046578,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315147,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056952,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.702792,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.213817,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612615,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786578,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.605108,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044318,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1718a2e148b9fc9c9f1eafdf4d0e1ad7392d88fc",
          "message": "Put the reason a fuzz job died into the issue it files (#2042)\n\nThe \"infrastructure or build failure\" issue could say no more than \"see the\nrun log\", so every instance costs a manual `gh api .../logs` to explain. That\nis worst for the failures it is most often filed for: a GitHub-hosted runner\nreclaimed mid-job *cancels* the job, which skips even the `if: failure()`\nupload step, so no artifact reaches the report job and the run log is the only\nsurviving evidence.\n\nThe report job already holds `actions: read`. Have it fetch each failed job's\nlog over the API and lead the issue with a per-job verdict — duration plus the\nlast few `##[error]` lines — recognizing the runner-shutdown line specifically.\nThat is the distinction the old text could not draw: a shutdown (exit 143) is\ninfrastructure and wants a re-run, whereas a job cancelled at its own\n`timeout-minutes` is worth chasing as a hang, since every generated program is\nindividually time-bounded.\n\n#2040 was the first kind wearing the second's clothes — an arm64 leg killed 46\nmin into a 55-min budget, on a commit whose x86_64 leg was entirely normal.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T08:06:10Z",
          "tree_id": "f8189011b69be162fedf37b3df55db8c9fa5825a",
          "url": "https://github.com/kaappi/kaappi/commit/1718a2e148b9fc9c9f1eafdf4d0e1ad7392d88fc"
        },
        "date": 1785589571359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.033689,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.357974,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569017,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.947608,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004975,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045086,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295084,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05506,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.306315,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.178694,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.533594,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308367,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685778,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.864144,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04535,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fad68505ef5ff7553608a2c119340300f3542d93",
          "message": "Phase 2.9: control-flow audit — 171 assertions, and a wrong-arity exception handler runs anyway with a leftover register as its third argument (#2039)\n\n* Phase 2.9: control-flow audit — 35 → 171 assertions\n\nprimitives_control.zig had 35 unnamed assertions from the v1 campaign and\nnothing at all for the mechanism that postdates it: SRFI 248's sticky\nexception handlers. This restates the old assertions with names and adds\nthe dimensions v1 did not have — the sticky-handler interactions with\ndynamic-wind, nested guard and resume; D1 (internal-primitive\nreachability); D2 (KP codes); D5 (which native callback sites can park a\nfiber).\n\nThe oracles are documents, as the campaign prefers: R7RS §4.2.7's two\nguard examples, §6.11's two worked examples, and all three of §6.10's\ndynamic-wind ordering rules are now pinned verbatim, with the two\nre-entry rules cross-checked against chibi-scheme.\n\nSix issues filed, none fixed here:\n\n  #2034  callHandler/callThunk skip the arity check, so a wrong-arity\n         exception handler, with-exception-handler thunk, call-with-values\n         producer or call/cc/call/ec receiver runs anyway, with surplus\n         parameters bound to leftover register contents\n  #2033  a top-level redefinition of call/cc, apply, eval or\n         call-with-values is ignored in tail position only\n  #2035  819 nested dynamic-wind extents abort with KP9001 \"internal\n         error\", and the failure is catchable\n  #2036  three diverging diagnostic paths in the control primitives\n  #2037  %unwind-to-escape is missing from internal_helpers\n  #2038  doc-truth: README and CONFORMANCE claim SRFI 248 has exactly\n         two caveats\n\n15 assertions are disabled with ;; FAIL: markers naming those issues, each\nsitting next to the enabled control that discriminates it — the\ndynamic-wind arity checks beside #2034, non-tail call/cc beside #2036,\nlocal shadowing beside #2033.\n\nGreen in ReleaseSafe, Debug, and -Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.9 in the audit tracker\n\nCites PR #2039 and the six issues it filed. The Status count line is\nleft to the orchestrator.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T14:18:33+05:30",
          "tree_id": "ecd40955e73b780518d2175ea8855fc0bd670e5f",
          "url": "https://github.com/kaappi/kaappi/commit/fad68505ef5ff7553608a2c119340300f3542d93"
        },
        "date": 1785591666234,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355716,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.594232,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.606951,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.997794,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004737,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04833,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315134,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057245,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.702092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216488,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582252,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287607,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815795,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.544461,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045507,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dfd8dff73d8749689a4918d4ab29549a20afbfeb",
          "message": "Phase 3.8: ten smoke-only SRFIs — 261 assertions, and two closed issues whose regression tests pinned the valid case (#2078)\n\n* Phase 3.8: ten smoke-only SRFIs — 67 → 261 assertions\n\nAudit v2 unit 3.8. Ten SRFIs whose test files existed but held ≤12\nassertions each: 23, 46, 98, 112, 139, 149, 188, 190, 236, 244. A smoke\ntest proves the library loads; it does not test the library.\n\nFour of the ten are genuinely thin by nature — 23 is one procedure whose\nspec explicitly declines to prescribe behaviour, 46/149 are bare\n(export syntax-rules) conformance statements, 244 re-exports a core\nspecial form — so the work went into the mechanism each one *claims*\nrather than the wrapper.\n\nTwo closed issues reproduce verbatim and were reopened:\n\n  #682  A pattern variable used at a LOWER ellipsis depth than it was\n        matched silently expands to (). The fix (PR #730) added a\n        `b.depth != 1` check to instantiateEllipsis; #931 removed it —\n        correctly, since it blocked legitimate nested reduction — and\n        nothing replaced it. The regression test the issue shipped only\n        ever exercised the VALID case, so it printed PASS throughout.\n        The depth-0 half, which #730 never touched, still carries the\n        comment admitting it.\n\n  #550  Top-level define-values ignores an arity mismatch. The fix\n        (153cefd8) added its checks inside the MultipleValues arm only;\n        the single-value arm has none, so three of the issue's four\n        reproductions still exit 0 with a prefix of the formals bound.\n\nOne new issue:\n\n  #2075 A begin-wrapped internal define in a let body escapes to the\n        global environment when no enclosing procedure exists. R7RS\n        4.2.3 requires the begin to be transparent; the unwrapped form\n        is correct everywhere, and the same text inside any lambda is\n        correct — so `(define g 'global)` followed by\n        `(let ((g 'outer)) (begin (define g 'inner)) g)` answers `outer`\n        and leaves the global reading `inner`. Found while checking the\n        claim lib/srfi/188.sld's header rests on, which turns out to be\n        true only at top level.\n\nSRFI 190 inherits #2060 exactly (make-coroutine-generator is call/cc\nbased, so a resume cannot cross a returned SRFI 1 native frame); cited\nrather than re-filed, with the (scheme base) map/for-each controls\npinned enabled beside it.\n\n11 assertions are disabled behind ;; FAIL: markers and every one was\nmutation-tested — each fails today, so a fix flips it. The\nbegin-splicing probes in srfi188.scm are evaluated at true top level and\nstashed in variables, because SRFI-64's own test-equal wrapper supplies\nthe enclosing procedure scope whose absence is the defect and answers\n`inner` from inside the assertion.\n\nClean on the rest: SRFI 139's adjustment reaches a macro defined before\nthe parameterize and is restored across a macro boundary; SRFI 149's\nsemantics rule 4 over a compound template element matches Guile (chibi\n0.12 does not); SRFI 46's custom ellipsis, tail patterns and their\ncombination are correct in all 24 probed shapes; SRFI 98's alist is\nfreshly allocated per call so a caller cannot corrupt the environment;\nSRFI 112 answers string-or-#f for all six with correct arity; SRFI 236\nevaluates every expression exactly once with no template capture.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Note in srfi244.scm that fixing #550 aborts the file at load\n\nThe three top-level probes pinning #550's silent cases are definitions,\nnot assertions, so a fix makes them raise while the file is loading. Say\nso where the fixer will read it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Pin the two-ellipses-in-one-pattern split (#2082)\n\nR7RS 4.3.2's pattern grammar admits at most one ellipsis per list or\nvector pattern; SRFI 46's tail patterns widen what may follow it, not\nhow many there may be. This expander accepts two and gives the trailing\npattern the last two elements regardless of input length, while a short\ncall fails outright. chibi 0.12 and Guile 3.0 both reject the\ndefine-syntax.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T14:34:24+05:30",
          "tree_id": "d4d8c6c053f982707aff31235b7b05102f78b63c",
          "url": "https://github.com/kaappi/kaappi/commit/dfd8dff73d8749689a4918d4ab29549a20afbfeb"
        },
        "date": 1785593450497,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.349359,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.000877,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.608617,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987852,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004748,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046844,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315527,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057966,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.740627,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.215363,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612104,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.291752,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80216,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.736928,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045488,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ae45e7871208e8399ebdf40600c290e7bec19a06",
          "message": "Require a priority label on every issue (#2090)\n\n* Require a priority label on every issue\n\nThe rubric landed in docs/dev/github-issues.md (#2032, #2041), but nothing\ntold a filer to apply it. The evidence that a document alone is not enough:\n41 issues were filed unlabeled while those two PRs were open, in bursts of\n6-27 as each audit phase completed. Triage after the fact means re-reading\nevery issue body to recover a judgement the filer had already made.\n\nPuts the decision table where it is needed at filing time, plus the four\nrules that settle the hard cases — critical is process-level unsafety only,\nreachability separates critical from high, an audit header's Severity is an\ninput rather than the answer, and silence moves an issue up within its level\nrather than between levels. The full rubric, worked boundary cases, and the\nlabel taxonomy stay in docs/dev/github-issues.md; this is the filing-time\nsubset.\n\nAdvisory only, like the neighbouring test and file-size rules: a CI gate\nwould have to run against the tracker rather than the diff, and the failure\nmode here is a missing label rather than broken code.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Make the priority-label audit catch double labels too\n\nReview of #2090: the prose requires exactly one `priority:` label, but the\ncommand only reported issues with zero. An issue carrying two was invisible\nto the very check meant to enforce the rule. Counts the labels and reports\nanything that is not 1, keeping the fuzz-finding exemption.\n\nFixed in docs/dev/github-issues.md as well as CLAUDE.md — the snippet was\ncopied from there, so the same blind spot shipped in #2032.\n\nNo issue in the tracker has ever carried two, so this finds nothing today;\nthat is the point. A check that cannot observe half of what it asserts would\nhave gone on reporting a clean tracker either way.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:03:55+05:30",
          "tree_id": "7e3074d63cf4ab1467be4765740eec1cddabb01f",
          "url": "https://github.com/kaappi/kaappi/commit/ae45e7871208e8399ebdf40600c290e7bec19a06"
        },
        "date": 1785594471481,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.548942,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.903786,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.362164,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.935329,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003779,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030209,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.192009,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.03609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.768757,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.772884,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.016314,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219299,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.132917,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.897927,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.030387,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "80553427120c666d034fcfa11af4268ae09f7552",
          "message": "Phase 3.4: SRFI 146 audit — 668 assertions over all 161 exports, and (srfi 146 hash) never uses the comparator it is given (#2070)\n\n* Phase 3.4: SRFI 146 audit — 668 assertions over all 161 exports\n\nSRFI 146's two libraries exported 161 names and its one manual-counter test\nfile touched 53 of them. Two new SRFI-64 files close that gap completely.\n\ntests/scheme/srfi/srfi146-reference.scm ports the SRFI's own reference suite\n(srfi/146/test.sld and srfi/146/hash/test.sld, MIT, Marc Nieper-Wisskirchen)\nverbatim apart from the library wrapper — 167 assertions, 7 disabled.\n\ntests/scheme/srfi/srfi146-differential.scm runs one parameterised body over\nboth libraries through an operation table, so the 66 names they share are\nchecked for agreement rather than against a hand-written expectation — 501\nassertions, 26 disabled. Nothing asserts hashmap iteration order.\n\nThe differential is what found most of it. (srfi 146 hash) discards its\ncomparator argument outright and keys every hashmap by equal?, so a\ncomparator whose equality is `=` merges 1 and 1.0 in the ordered library and\nsplits them in the hash one. Both constructors also give the LAST duplicate\nkey precedence where the spec says the first — the one distinction the spec\ngoes out of its way to contrast with mapping-set, and mapping-adjoin and\nalist->mapping are both correct, which is what makes it a defect rather than\na convention.\n\nFiled #2044 (comparator discarded), #2045 (duplicate-key precedence), #2046\n(mapping-key-predecessor/-successor invoke failure unconditionally), #2047\n(=? omits the key-comparator identity check), #2048 (make-mapping-comparator\nsupplies no ordering and make-hashmap-comparator no hash), #2049\n(hashmap-ref/default calls a procedural default), #2050 (any?/every? return\nthe predicate's value), #2052 (the single-mapping comparison form), #2053\n(mapping-map and mapping-find run their fold twice). Commented on #2023 with\nthe wider blast radius through this SRFI's own API.\n\nClean and now pinned rather than assumed: all four mapping-search\ncontinuations on both libraries, escaping continuations out of every\nhigher-order entry point, the purity of all eight pure/linear pairs, the\nwhole ordered surface (min/max, predecessor/successor, the five ranges,\nsplit, catenate, map/monotone, fold/reverse), set algebra on disjoint,\nidentical and overlapping inputs, mixed-type default-comparator keys, and\n1000 inserts plus 1500 interleaved insert/delete rounds against a red-black\ndelete that never rebalances.\n\nFound by: Systematic audit v2, Phase 3.4 (tracking #1890)\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Pin the #2023 cliff, not a miss count — the Debug leg found the keys\n\n`(> (hash-misses 12 40) 0)` asserted that the bug is still present. It\npassed on macOS ReleaseSafe and failed on CI's `ubuntu-latest, Debug` leg,\nreproduced locally in a Debug build.\n\nPast the depth limit the hash degenerates to the key's pointer, so whether\ntwo structurally-equal keys collide is an accident of allocation. Measured\non one ReleaseSafe binary: 31 and 32 misses of 40 at `deep 8` across two\nruns, then 3 vs 40 of 40 at `deep 9`. Debug finds far more. No miss count\nis assertable past the limit, in either direction.\n\nWhat is stable in every run and both builds is the cliff itself, so that is\nwhat this pins now: 0/40 misses at every depth from 1 to 7.\n\nNote `deep` builds a FLAT list of length depth+1, not a nested structure,\nand the hash walks the spine — so the limit is reached at `deep 8`\n(length 9), and `deep 7` (length 8) is the last fully findable case. The\nfirst attempt at this fix used `deep 8` and failed for that reason.\n\nVerified: Debug 501/501, and 0 misses at depths 1-7 across runs in both\nbuild modes.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:09:16+05:30",
          "tree_id": "a9dbc360b8ceac0347872608c15025ebb4e5a8c8",
          "url": "https://github.com/kaappi/kaappi/commit/80553427120c666d034fcfa11af4268ae09f7552"
        },
        "date": 1785595426327,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.910995,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.799274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568073,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.804383,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004907,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044907,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291523,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.295892,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15296,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.512446,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306443,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.677539,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.802883,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045463,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c83f07a6bb79eeb1be27380bb87f460674f10af9",
          "message": "Phase 3.6: SRFI 158 audit — 349 assertions over all 55 exports (#2068)\n\n43 of SRFI 158's 55 exported names appeared in no test. The reconnaissance\npass had spot-probed 18 of them and found nothing, so this unit was scoped as\nclosing a measurement gap rather than a bug hunt, with effort ranked toward\nthe three places a generator library actually breaks. Two of those three came\nback clean and are now pinned rather than assumed:\n\n  * Laziness — every combinator's construction is instrumented with a\n    call-counting source and asserted to consume zero. gmerge is the one\n    exception (it primes both inputs at construction); that is the reference\n    implementation's design, chibi agrees, and the spec constrains only merge\n    order, so it is pinned as documented behaviour.\n  * Exhaustion — all 12 constructors and all 18 combinators are drained and\n    then called three more times. Every one keeps returning eof.\n  * Infinite sources — 37 compositions of an endless generator with a bounded\n    consumer, all under run_timeout during development. No hangs.\n\nThe bugs were elsewhere, and each has its own root cause:\n\n  #2055  make-range-generator does not begin the sequence with an inexact\n         start. The (- (+ start step) step) round trip that carries exactness\n         contagion also perturbs a start that is already inexact — and when\n         step is much larger, annihilates it: (make-range-generator 1e-20 1.0\n         1.0) begins at 0.0. make-iota-generator, with identical \"begins with\n         start\" wording, is correct at every one of those inputs, and so is\n         make-range-generator's own one-argument form.\n\n  #2057  gflatten raises on an empty list from its source. Its refill runs\n         once instead of looping, so (car '()) escapes. A filtering gmap that\n         yields '() for rejected elements is the natural way to hit it.\n\n  #2060  SRFI 158's own generator-unfold example does not run. SRFI 1's\n         higher-order procedures, hash-table-walk, and assoc/member with a\n         predicate are still native drivers, and four SRFI 158 constructors —\n         including gtake — are coroutine-backed, so a resume crosses a\n         returned native frame. make-for-each-generator's stated job of\n         converting \"any collection\" fails for a hash table, and fails on the\n         *second* call, not the first. #1347 closed this for the map family;\n         SRFI 1 was never in its scope. CONFORMANCE.md cites a README section\n         for the restriction that does not state it.\n\n13 assertions are disabled against those three; the mutation test enables them\nand exactly those 13 fail. Nine controls are enabled beside them, so a fix\nflips both sets.\n\nTwo portability traps worth carrying: never write (list (g) (g)) — chibi\nevaluates arguments right to left, so the same generator yields the reverse\nsequence and the file only looks correct on one implementation — and an\naccumulator's return value for a non-eof argument is explicitly unspecified,\nso only its eof value is asserted anywhere here.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:12:04+05:30",
          "tree_id": "071726d345164485a54197d7e6b0d6be92b274f9",
          "url": "https://github.com/kaappi/kaappi/commit/c83f07a6bb79eeb1be27380bb87f460674f10af9"
        },
        "date": 1785598662413,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.924445,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.522821,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.556833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.80722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004842,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04511,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291488,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054834,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.294553,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535459,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303796,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.677471,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.770293,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044913,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "22a8930f764e725c9df4e156a3ea15abaa55efa1",
          "message": "Stop pinning an exact atime in the filesystem audit (#2077) (#2091)\n\nThree assertions in tests/scheme/audit/primitives_filesystem-audit.scm\npinned an exact access time. Nothing can hold st_atime still: any read by\nany process — an indexer, a backup agent, an AV scanner, the periodic /tmp\ncleaner — moves it to \"now\". It flaked in ~2 of 9 parallel corpus runs,\nreporting the current epoch second where the set value belonged.\n\nReproduced deterministically rather than by re-running until it broke:\n\n    set-file-times p 1000000 2000000\n    before reader: atime=1000000     mtime=2000000\n    (call-with-input-file p read-char)      ; one read, what a scanner does\n    after  reader: atime=1785575578  mtime=2000000\n\n    OLD  (= atime 1000000)  => #f     ← the flake\n    NEW  (>= atime 1000000) => #t\n    mtime still exact       => #t\n\nmtime now carries the discrimination. No reader changes it, and it alone\nseparates all three cases (set / both sentinels / atime sentinel with a\nreal mtime). atime is asserted as \"not earlier than what we set\" — the\nstrongest true statement available, since an intervening reader can move it\nforward but never backward.\n\nEach case also takes one file-info and reads both fields from it, instead\nof stat'ing twice for the two halves of one assertion.\n\nThis is the same class as #1993 from the same unit: an assertion that held\nonly because the machine happened to be quiet. 427 -> 430 assertions (three\ncombined assertions became six).",
          "timestamp": "2026-08-01T17:12:51+05:30",
          "tree_id": "f4264a049bcf568fd20a98c74f06c34f6ab4217f",
          "url": "https://github.com/kaappi/kaappi/commit/22a8930f764e725c9df4e156a3ea15abaa55efa1"
        },
        "date": 1785599671803,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.921249,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.784503,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559102,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.807649,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004861,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044745,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.292137,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055107,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.288358,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.155191,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.508512,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306209,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.668407,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.800001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044915,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fc66b3c47104e4272ff2209622f0765d38533304",
          "message": "Phase 3.5: SRFI 166 audit — 244 assertions across all 89 exports, and pretty never breaks a line at any width (#2069)\n\n* Phase 3.5: SRFI 166 audit — 245 assertions across all 89 exports\n\nThe unit was scoped as closing a measurement gap: 52 of 89 exported names\nnever appeared in a test file. The gap turned out to be hiding a library\nthat is largely a skeleton, so the suite is written against the SRFI's own\nspec page rather than against the implementation, and every expected value\nis either quoted verbatim from one of the spec's \"=>\" examples or derived\nfrom a sentence of its prose cited in a comment.\n\n188 assertions pass; 57 are committed disabled with a `;; FAIL: #NNNN`\nmarker naming the issue. Uncommenting the disabled set makes exactly those\n57 fail and leaves all 188 passing, in both ReleaseSafe and\n-Dgc-stress=true.\n\nEleven issues, one per root cause:\n\n  #2054  fn and with are procedures where the spec defines macros, so every\n         documented use of the state-variable API raises \"not a procedure\";\n         fn additionally binds nothing, computing its bindings and\n         discarding them, and the `output` state variable has no slot\n  #2056  with restores the whole 13-slot state vector, so col and row are\n         rolled back and output written inside a with is invisible to the\n         space-to / tab-to / fl that follow it\n  #2058  tab-to emits a full tab width when already on a tab stop, which\n         the spec calls out explicitly; tab-width 0 divides by zero\n  #2059  escaped wraps its output in quote delimiters the spec does not add\n         and ignores esc-ch/renamer; maybe-escaped never quotes on an\n         embedded quote character\n  #2061  the numeric family reads only num/radix/precision: sign-rule,\n         comma-rule, comma-sep and decimal-sep are ignored, radix is\n         dropped as soon as precision is given, numeric/comma inserts no\n         commas at all, and numeric/si ignores its base and separator\n  #2062  padded/trimmed/fitted measure with string-length, so the ellipsis\n         and string-width state variables are never read\n  #2063  displayed renders a formatter argument as #<procedure>\n  #2064  pretty is write — it never breaks a line at any width — and\n         written-shared/pretty-shared do not label shared structure\n  #2065  columnar and tabular do not align, wrapped hardcodes width 78,\n         wrapped/char and justified are aliases of wrapped, line-numbers\n         is not a stream; the SRFI's own nl(1) example produces garbage\n  #2066  (srfi 166 unicode) is a stub: substring-terminal-width returns an\n         integer where the spec returns a substring, string-terminal-width\n         is string-length, terminal-aware is a no-op\n  #2067  15 documented names are not exported and (srfi 166 base) does not\n         exist, while (cond-expand (srfi-166 ...)) answers yes\n\nCorrect and asserted as such: all 23 (srfi 166 color) exports, including\nthe exact SGR codes for the 16 foreground/background colours, the three\nstyles, and both the 8-bit cube and 24-bit true-colour forms; the whole\njoined family; every non-ellipsis trimming case including the odd/even\nasymmetry; fitted in all three directions; forked, call-with-output,\nfrom-file, upcased and downcased (with the spec's Greek word-final sigma);\ncycle detection in written and pretty; and pretty's read-back round trip.\n\nTwo portability notes the file documents inline. Non-ASCII text is written\nwith \\x...; escapes so the assertions are byte-stable on every CI leg, and\nno assertion consults the ambient terminal width. Also worth knowing:\n#\\x1b; is not a hex character escape — R7RS spells the in-string form\n\"\\x1b;\" with a terminating semicolon and the character literal #\\x1b\nwithout one, so #\\x1b; reads as ESC followed by a comment that swallows\nthe rest of the line. The suite uses (integer->char 27).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Drop the one disabled assertion that would not flip on its own fix\n\n\"fn: a binding is visible to the body under the procedural form\" asserted\na value this implementation's calling convention never defined — there is\nno way to *name* an fn binding under the procedural form, so the assertion\nfailed only incidentally, and #2054's fix (making fn a macro) would have\nrequired deleting it rather than re-enabling it. A `;; FAIL:` marker\npromises the opposite.\n\nThe three remaining #2054 assertions cover the same defect in the spec's\nown terms, where the fix does flip them. 244 assertions: 188 enabled,\n56 disabled; the mutation test is still exact.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T17:18:11+05:30",
          "tree_id": "427e7d1dcb2fd66e6809fdc0409f646f651e5dac",
          "url": "https://github.com/kaappi/kaappi/commit/fc66b3c47104e4272ff2209622f0765d38533304"
        },
        "date": 1785601100379,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.917303,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.035669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573342,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.816125,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00484,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044874,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.292346,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05462,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.295172,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151661,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307154,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.676451,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762969,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044827,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b5c4e21be3a1f4aba2816a19ef925b2db2b02f6",
          "message": "Phase 2.8: hash-table audit — 201 assertions, and equal? tables lose any key deeper than 8 (#2031)\n\nThe 268-line audit test asked its hash/equality-consistency questions only\nat depth <= 2, so a green suite never noticed that `valueHashDepth` stops\nrecursing at MAX_HASH_DEPTH = 8 and returns the *pointer* of whatever sits\nat the cutoff. A nine-cons-cell key is enough: 200 of 200 freshly-built\ntwelve-element keys are unfindable, while the eight-element control misses\nnone. Closed #1180 named this exact residue in its own suggested fix and\nshipped only the bignum/rational half.\n\nTwo more, both new: a custom hash procedure that inserts into its own table\nmakes `rehash` keep iterating an entry array the nested rehash already\nfreed, aborting the process with empty stdout *and* stderr; and all four\nhash procedures mask to 62 bits and then hand the result to a 48-bit\n`makeFixnum`, so about half of them come back negative.\n\nEvery assertion now carries a name string, and the file states two standing\nportability rules for itself: never assert a hash value derived from a\npointer or from `usize`, and never assert iteration order.\n\nAll 8 callback sites were probed under mutation, raise, re-entry and\nblocking. Only the custom-hash site is unsafe. walk and fold are correct on\nevery route tried, and the path needs no blocking guard — a channel call\n6000 native frames deep inside a walk callback works, where the custom-port\npath aborts at 3000.\n\nIssues: #2023, #2024, #2025. D2 taxonomy for this file is already #2021.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:05:41+05:30",
          "tree_id": "aae5667abea94253644f4bc9d78b6cbffeee55c0",
          "url": "https://github.com/kaappi/kaappi/commit/6b5c4e21be3a1f4aba2816a19ef925b2db2b02f6"
        },
        "date": 1785601121553,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.038887,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.67648,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.441208,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.175095,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227322,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043156,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.132385,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.931104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.210737,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.231549,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.319837,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.733514,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035748,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ca8f28d00d7d1f84d0d5bfa0f7ee8323a126821",
          "message": "Phase 3.9: eight large-and-thin SRFIs — 1579 assertions, and bitvector-logical-shift shifts the wrong way (#2095)\n\nEight SRFIs with substantial export surfaces and thin tests: 113, 225, 178,\n152, 240, 189, 35, 27. Coverage of exported names goes from 288/456 to\n441/456; assertions from 495 to 2074.\n\nThe unit was scoped as a measurement gap, and the strategy doc is explicit\nthat a high untested-export count is not itself evidence of bugs. It found\nsix anyway, because two of these SRFIs had a real oracle available:\n\n  * SRFI 178's own reference implementation loads into this build as an\n    alternate library. Diffing all 107 exports against it over a\n    523,361-check corpus left exactly three divergences — one real bug\n    (#2083), one shrinking-`pad` case the spec leaves ambiguous (not filed,\n    documented in the suite header), and nothing else. That is a much\n    stronger statement than any hand-written suite could make.\n  * SRFI 113 has both a reference implementation and chibi-scheme. Where the\n    three disagree the suite says which is right and why: three chibi\n    defects are asserted in Kaappi's favour, and two Kaappi defects are\n    disabled with the reference's own code quoted.\n\nFindings, all reproduced on a fresh ReleaseSafe build with a discriminating\ncontrol:\n\n  #2083  bitvector-logical-shift moves bits toward higher indices for\n         count>=0 and lower for count<0 — inverted on both branches, and it\n         fails the two assertions in SRFI 178's own test/quasi-ints.scm.\n         count=0 is correct, which is the control.\n  #2084  bitvector-segment conses outside its recursive call, so a legal\n         200,000-bit vector with n=1 dies of an *uncatchable* KP3008, and\n         n=0 recurses without bound instead of raising. 1,000 segments is\n         the control. The reference validates n and delegates to a map.\n  #2085  bag-increment! ignores the spec's \"but not less than zero\", and the\n         resulting negative multiplicity makes bag->list, bag-fold and\n         bag-for-each loop forever on `(= i count)`. bag-product with a\n         negative n is a second route. Zero and positive counts terminate.\n  #2086  set->bag! leaves an element already in the bag at its old count;\n         the reference and chibi both increment.\n  #2087  SRFI 189 exports 24 names of the spec's 82, four of the present\n         ones have narrower signatures than the spec, `either` is exported\n         but never defined — and cond-expand answers yes to both srfi-189\n         and (library (srfi 189)). The three monad laws and both functor\n         laws are asserted as properties over five payloads and all hold.\n  #2088  An R7RS define-record-type produces an rtd whose own_field_names is\n         empty, so record-type-field-names returns #() for a record that has\n         fields and record-accessor/mutator/field-mutable? are unusable —\n         the exact interoperability SRFI 240 exists to provide. The R6RS\n         clause syntax and make-record-type-descriptor are the controls.\n\nClean results worth recording, since they are what the measurement was for:\n\n  * SRFI 225's generic layer agrees across all three DTOs on 49 of 51\n    operation groups; the two that differ do so correctly (dict-ref with no\n    failure raises everywhere, dict-pure? is what tells the two apart). All\n    35 proc-id tags are exercised through dto-ref for the first time.\n  * SRFI 152 cannot diverge from SRFI 13 at all: the .sld imports those 22\n    names straight from (srfi 13), so they are the same binding. Asserted by\n    identity, which doubles as a gate if anyone reimplements one. Gone\n    deliberately shallow otherwise — #1234 already audited 152 in v1 and its\n    20 remaining untested exports are (scheme base) re-exports.\n  * SRFI 27 is correct on every axis a random source can be pinned on:\n    range and exclusivity of both bounds, exactness, bignum bounds,\n    pseudo-randomize reproducibility and independence, and state\n    capture/restore including mid-sequence and across sources. Stable over\n    three consecutive runs.\n  * SRFI 35's condition world and R7RS's error-object world are disjoint and\n    self-consistent in both directions. Not a defect, but nothing pinned it.\n\nAll 32 disabled assertions were mutation-tested by enabling each one alone in\nits own copy of the file: 30 fail, one errors, one hangs. None pins nothing.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:19:40+05:30",
          "tree_id": "5438004f1124f0c6e8d88aa97e30e358117ab012",
          "url": "https://github.com/kaappi/kaappi/commit/5ca8f28d00d7d1f84d0d5bfa0f7ee8323a126821"
        },
        "date": 1785601219515,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348726,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.669102,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612807,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.029662,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004787,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046996,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315838,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057256,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.706146,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.590027,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28993,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.807711,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636382,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04595,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "70675ffae061552ebbb9a2373e45dae431353560",
          "message": "Phase 6B: reconcile kaappi test with run-all.sh — a suppressed (exit 0) still meant exit 0 (#2081)\n\n* Phase 6B: reconcile kaappi test with run-all.sh — a suppressed (exit) still has semantics\n\nThe two runners disagreed on tests/scheme/srfi/srfi150.scm: green under\nrun-all.sh, `1 errored` and exit 1 under `kaappi test`, with a summary that\nread as self-contradictory (`0 failed` tests above `1 failed` files). Every\nunit of the audit campaign has been reporting it as noise, and it is what\nblocks `kaappi test` from replacing the legacy runner.\n\nThe cause is not `test-expect-fail`, where the finding pointed — those\nannotations only decide whether the orphaned assertions land in `xfail`\nrather than `fail`. It is the file's own exit status. srfi150.scm provokes an\nuncaught top-level error and then calls `(exit 0)` on the SRFI-64-clean path,\ndeliberately. A plain run honours that, so run-all.sh reads 0 and says PASS.\nThe `kaappi test` worker sets `suppress_exit` so the file's `(exit)` cannot\nrob it of the chance to emit a result — but it then reported `script_had_error`\ndirectly, never consulting what the suppressed call had asked for.\n\nrun-all.sh was right. tests/scheme/errors/exit-code.sh already pins the rule a\nplain run follows, with its own regression test: an explicit `(exit N)` wins\nover an already-reported top-level error. And this was a gap rather than a\npolicy — `emitResult`'s own doc comment claimed `errored` covered \"a nonzero\n`(exit)`\", which the code never did. Suppressing the termination was never\nmeant to also discard the status.\n\nSo the semantics are reapplied where the verdict is formed, in one function\nwith all three facts in hand. An `(exit 0)` waives the file's own top-level\nerror; it can never bury a failing assertion, because the counters stay\nauthoritative. A nonzero exit the counters already explain stays redundant, as\nbefore — calling it an error would trade per-assertion detail for a bare ERROR\nline. A nonzero exit they do not explain is now an error, which closes the\nopposite-direction divergence nobody had noticed: such a file was FAIL under\nrun-all.sh and silently PASS here.\n\nNothing goes quiet. A waived error becomes a note — carried in error_message\nwith error:false, printed under the file's verdict line with the worker's own\ndiagnostic, and tallied as `noted` in both summaries. The first summary line is\nrelabelled `Tests:`, since it counts tests and the line under it counts files.\n\nVerified by running both runners' verdict rules over all 352 SRFI-64 files:\n1 disagreement before, 0 after. srfi150.scm is the only file repo-wide in this\nstate, and it is untouched by this change.\n\nrunner-agreement.sh is the gate that keeps it that way: seven fixtures, each run\nthrough both rules, which must agree and land on the expected verdict. Its first\nfixture rebuilds srfi150's shape from scratch, so the guarantee outlives #2051\nfixing SRFI 150. Reverting resolveVerdict kills 3 of its 10 assertions, in both\ndirections.\n\nCloses #1903.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Record the runner-agreement fix in the changelog\n\nThe changelog gate is right to fire here: this changes what `kaappi test`\nreports for a real class of file, which is user-visible behaviour, not a\nrefactor.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:29:58+05:30",
          "tree_id": "a20f5d30d65ea1222a32cdc4d69cc923a5e1e4d9",
          "url": "https://github.com/kaappi/kaappi/commit/70675ffae061552ebbb9a2373e45dae431353560"
        },
        "date": 1785601242778,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.268112,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.567725,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569836,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.977499,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00466,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046511,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314248,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0571,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.695347,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224677,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.57476,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282775,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.768204,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.464813,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044264,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e699b451536d8200d76cfe0d5ed71e2f98f905f8",
          "message": "Phase 3.10: un-quarantine the SRFI 257 reference suites; re-triage SRFI 150 (#2071)\n\ntests/scheme/srfi/slow/ held the two full SRFI 257 reference suites and no\nrunner reached it: run-all.sh's globs are non-recursive (kaappi#1900). The\nquarantine's premise was wall-clock — the headers claimed 4.5 and 1.5 minutes\nof macro expansion against a 60s per-file budget. Both now run in ~0.4s.\n#1802/#1804 (ReleaseSafe was memsetting the expander's 1MB buffers on every\nexpansion) obsoleted the quarantine eight days after it went in, and nothing\nre-measured, because nothing ever reported the files as missing.\n\nMove both up into tests/scheme/srfi/ rather than teaching run-all.sh one more\nglob: that keeps the invariant \"subdirectories hold fixtures, suite files sit\nat the top level\" intact, and needs no change to the 18 CI legs that run this\nscript. They rank 6th and 7th slowest of 202 srfi files; five already-enabled\nfiles are slower, so the budget argument is settled by a wide margin.\n\nThey do not supersede the lean srfi257.scm / srfi257-rx.scm: 18 of 34 and 8 of\n25 of those assertions have no counterpart in the full ports, so both are\nkept. That made their SRFI-64 suite names collide — the only two duplicate\ntest-begin names in the tree, and SRFI-64 derives its log filename from the\nsuite name — so the full ports are renamed to srfi-257-full / srfi-257-rx-full.\nNet: +131 assertions for ~0.8s.\n\nrun-all.sh gains a reachability check so this cannot recur silently. It fails\nthe run if any .scm under a suite subdirectory contains test-begin. Fixtures\nare exempt by construction (a fixture never opens a SRFI-64 suite), verified\nagainst the whole tree: 11 fixture files under suite subdirectories, zero\nfalse positives, and the check is mutation-tested in both directions.\n\nSRFI 150's four expected failures are re-triaged. They cited closed #1832;\nthat attribution is wrong on both halves. #1832 is fixed — its own regression\ntest passes and its exact shape works under plain (scheme base)\ndefine-record-type — and a pre-existing top-level binding, #1832's defining\ncondition, is not required here at all: removing it leaves every case failing\nidentically. They are also not #2003, which needs the captured global to hold\na procedure. All four are one new defect, kaappi#2051: lib/srfi/150.sld\ncarries field names to run time inside quote, and quoting strips the hygiene\nrename, so two hygienically-distinct fields collapse into one. The expansion\nitself is correct. The library header's claim that the rename survives that\nboundary is corrected in place.\n\nThe annotations' structure is deliberately left alone so #1903 keeps its\nreproducer; that issue's own text contemplates restructuring this file as one\npossible resolution, which is 6B's call to make, not this PR's.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:09:13+05:30",
          "tree_id": "a69c0245756d44d237d4df5d27d334d9a764413f",
          "url": "https://github.com/kaappi/kaappi/commit/e699b451536d8200d76cfe0d5ed71e2f98f905f8"
        },
        "date": 1785604353533,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.285411,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.136965,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.581225,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.010866,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048087,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318348,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05728,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.677152,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.228172,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580147,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.292904,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782904,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676398,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04602,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7c564fe00696c8aaf929c42b371c5b67e810495d",
          "message": "Phase 3.7: eleven untested SRFIs — 271 assertions, and a use-site local named after a keyword captures it in every macro template (#2076)\n\n* Phase 3.7: eleven untested SRFIs — 271 assertions, and a use-site local named after a keyword captures it in every macro template\n\nEleven SRFIs had no test file at all: 2, 8, 11, 16, 28, 31, 34, 111, 145,\n222, 229. All eleven now have one, and all eleven answer their `srfi-N`\ncond-expand identifier — which is what made the gaps below invisible.\n\nThree files rather than eleven. SRFI 2 and SRFI 222 each carry a filed\ndefect, so each gets a self-contained file a fix PR can re-enable whole.\nThe other nine are 1-4 exports apiece with nothing filed against them;\nthey share one hygiene harness and one set of cross-SRFI composition\nassertions, so batching them beats nine near-empty files.\n\nEight of the eleven are correct against their own spec and against\nchibi-scheme 0.12.0 on every probe: 8, 11, 16, 28, 31, 34, 111, 229 —\nincluding all of SRFI 229's three worked examples, all of SRFI 34's six,\nall three of SRFI 11's, and SRFI 16's `plus`. SRFI 145 is correct too;\nits failure path errors where chibi returns #f, which is the reference\nimplementation's own debug-mode behaviour.\n\nThree issues filed:\n\n- #2072 (srfi 222) implements 5 of the spec's 10 procedures —\n  compound-map, compound-map->list, compound-filter, compound-predicate\n  and compound-access are simply absent, and the last two are what the\n  SRFI's own rationale is built around. Of the five that exist,\n  make-compound does not flatten nested compounds and compound-subobjects\n  raises on a non-compound instead of returning a one-element list, though\n  its two siblings compound-length and compound-ref both have the\n  non-compound arm and both behave correctly.\n\n- #2073 SRFI 2's `(and-let* ((x 1)))` returns #t, not 1. The spec's own\n  denotational semantics is explicit — eval[(AND-LET* (CLAW))] =\n  eval_claw[CLAW] — and chibi returns the claw value for all three claw\n  shapes. lib/srfi/2.sld folds the no-claw and last-claw base cases into\n  one rule that always yields #t.\n\n- #2074 A use-site local binding named after a syntactic keyword captures\n  that keyword inside any macro template. 15 of 17 keywords probed —\n  including begin, lambda, quote, letrec, cond, case, and, or, do, set! —\n  so `(let ((begin 5)) (m 7))` compiles m's `(begin e)` template as the\n  procedure call `(5 7)`. Chibi gets 16 of 17 right. The guard at\n  src/ir.zig:620 states the intended exemption in its own comment but\n  cannot deliver it: a template-introduced keyword never acquires a\n  `__hyg_N_` prefix, so isLexicallyBound decides the case. This is the\n  mirror image of closed #788, whose fix added that guard. It reaches two\n  shipped libraries here — SRFI 31's `rec` (via letrec) and SRFI 8's\n  `receive` (via lambda).\n\n39 assertions are disabled behind those three plus #2003 (which SRFI 8's\nreceive and SRFI 145's assume both reproduce, via call-with-values and\nerror respectively) and #1932 (a box built on a worker thread comes back\nwith box? => #f — the same defect Phase 5C found for a user-defined\nrecord, now reaching a spec-mandated type). Every disabled block was\nmutation-tested: uncommented, exactly those assertions fail, and two\n#f-expecting SRFI 222 assertions were rewritten as `(list … 'ran)` after\nthe mutation test showed they passed vacuously on an undefined-variable\nraise.\n\nTwo behaviours pinned as observed rather than filed, because chibi\nproduces byte-identical output: SRFI 28's `format` emits a trailing tilde\nand an unknown directive literally where the SRFI's reference\nimplementation raises (the Specification prose mandates an error only for\ntoo-few values), and `~A` is not `~a` — it passes through *without*\nconsuming its object, so a later `~a` silently takes the wrong argument.\nKaappi's `~a` on a nested list is the one place it beats chibi: R7RS\n6.13.3 requires nested strings and chars to be unescaped, and only Kaappi\ndoes that.\n\nRefs #1890.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Shrink the 200k format assertion — it was 35.7s of a 36s file (#2100)\n\nThe assertion is about recursion depth, and 10,000 frames exercises that.\nBut `format` walks its argument with `string-ref`, which is O(k) here\nbecause Kaappi indexes strings by codepoint over UTF-8 bytes — so the call\nis O(n^2):\n\n    input     format    bare string-ref loop   read-char from a string port\n     10,000     88 ms                 88 ms                           1 ms\n     50,000  2,181 ms              2,173 ms                           4 ms\n    100,000  8,691 ms              8,738 ms                           7 ms\n    200,000 35,756 ms\n\nstring-ref is essentially 100% of the cost, and the doubling steps confirm\nthe exponent (2x input -> 3.98x and 4.11x time). Filed as #2100, together\nwith the 20 other portable .sld files that use the same index-loop idiom.\n\nAt 200,000 this blew the 60s per-file budget on four CI legs — ubuntu\nReleaseSafe and Debug, freebsd-test, netbsd-test — while passing on a\ndeveloper Mac in 36s. The whole file now runs in 0.165s, same 196\nassertions.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:28:25+05:30",
          "tree_id": "95795263e749b8a6b00fd67de805fb5d71c75848",
          "url": "https://github.com/kaappi/kaappi/commit/7c564fe00696c8aaf929c42b371c5b67e810495d"
        },
        "date": 1785606223661,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.274088,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.09732,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571379,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.975592,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004625,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046744,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313726,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057059,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.657892,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224925,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58126,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281032,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782276,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596332,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045371,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f04aa5a75fa7bfe12381d1732ebaeb88787f7b7e",
          "message": "Phase 4A: derive isRejectedFormHead — the one missing name was define-property, and it was live on cond/case/do (#2092)\n\n* Phase 4A: derive isRejectedFormHead from the eval-fallback set\n\nThe native backend had two gates against splitting a lexical scope across\nthe native/interpreted boundary, and only one of them was derived.\n`ir.eval_fallback_form_names` is comptime-built from `llvm_node_table`,\nevery `FormKind` field, and `other_special_forms`; `isRejectedFormHead` —\nwhich gates cond/case/do through `exprNativeEmittable` — was a literal\n32-name array standing parallel to it. Parallel lists drift, and this one\nhad: `define-property` was in the derived set and absent from the array.\n\nThat was not latent. `define-property` is a compile-time form —\n`compileDefineProperty` evaluates its expression and stores the property\nwhile the enclosing form is compiled — and the interpreter compiles a\ntop-level `cond` whole, so the effect lands ahead of the clause body. With\nthe name missing, the backend emitted the cond natively and left only the\nregistration behind as a run-time `kaappi_eval`, moving that effect after\nthe rest of the body: `PBC` interpreted, `BPC` compiled. `case` diverged\nthe same way, and `do` did not compile at all (KP9001), because `emitDo`\ninstalls loop-variable locals before reaching the deferred form and\n`emitFormEval` refuses to eval inside a lexical scope.\n\n`rejected_form_heads` is now\n`(eval_fallback_form_names \\ derived_exclusions) ∪ extra_rejected_heads`.\n`derived_exclusions` is empty. `extra_rejected_heads` holds the six names\nthis gate rejects for its own reasons — `lambda` and `define`, lowered\nnatively elsewhere but not in sub-expression position here, and the four\nsyntax-position markers `unquote`/`unquote-splicing`/`else`/`=>`, which\nmust stay out of the derived set or `sexprNeedsEvalFallback`'s blind\nrecursion would reject every natively-lowered cond with an else clause.\nBoth lists now carry their reasons in code.\n\nA comptime block rejects a stale exclusion, an extra that duplicates a\nderived name, and any derived name that escapes the gate. The runtime test\nis deliberately stricter than the comptime invariant: it permits no\nexclusions at all, so weakening the gate takes two deliberate edits rather\nthan one quiet line. A second runtime test asserts the emitter behaviour,\nsince a correct list nothing reads would pass every list-level check.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Record the isRejectedFormHead fix in the changelog\n\nThis changes what the native backend emits for a real form, which is\nuser-visible behaviour rather than a refactor, so the gate is right to\nrequire an entry.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:52:25+05:30",
          "tree_id": "9ad05ae621efe0d3e61d5136c28e57b32aaf7a7e",
          "url": "https://github.com/kaappi/kaappi/commit/f04aa5a75fa7bfe12381d1732ebaeb88787f7b7e"
        },
        "date": 1785606301182,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961793,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.753976,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575551,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.823901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044619,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297449,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054999,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.305794,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156004,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.618274,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.312044,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.682164,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.827887,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045445,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5681053f9c173173264bb359f8cbf024f94f85f3",
          "message": "Make a fuzz overrun reportable, and stop it destroying its own evidence (#2094)\n\n* Report a fuzz job killed by its own timeout\n\nA job killed by `timeout-minutes` is CANCELLED, not failed, and it cancels the\nwhole run with it — so the report job's bare `if: failure()` was false and the\njob was skipped. The single outcome this workflow most wants to hear about, a\nfuzz leg overrunning its budget, filed nothing at all. Verified live: #2040's\nre-run burned its full 55 minutes and produced no issue.\n\nGate the job on `failure() || cancelled()`, and inside the step decide by the\ncheck-run annotation: a leg carrying `exceeded the maximum execution time`\nreaches the infra issue (including when a sibling leg's crash artifact would\notherwise have been the only thing filed), while a plain manual or concurrency\ncancellation still files nothing.\n\nThe annotation is also the only durable evidence a timeout leaves — a cancelled\njob's log blob is frequently never archived, and #2040's re-run answered\nBlobNotFound while its annotation was intact — so the verdict now reads logs\nand annotations together. The runner-shutdown line lives only in the former,\nthe timeout message only in the latter.\n\nThat same re-run disproved the shutdown verdict this file shipped hours ago:\nit claimed a reclaimed runner meant \"not a hang… re-run the job\", when in fact\nthe shutdown had masked an overrun already in progress on that very leg. It now\nsays a shutdown does not certify the job was healthy, and to check the leg's\nelapsed time against its history.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Keep a fuzz overrun's evidence instead of destroying it\n\nAn overrunning fuzz job erased everything needed to diagnose it. Reaching\n`timeout-minutes` cancels the job; a cancelled job skips its `if: failure()`\nupload, so nothing is captured — and the corpus it started from is never\nwritten back (save-on-success) and is eventually LRU-evicted. By the time\n#2040's arm64 overrun was investigated, no copy of the input set that\nprovoked it existed anywhere, and it is still unexplained.\n\nBound the fuzz command itself with `timeout`, derived as the job budget minus\n8 minutes so the two cannot drift. The step now fails on its own terms while\nthe job is still alive, so the upload runs — and it carries the whole corpus\nand coverage map plus `fuzz-state.txt`, an mtime-ordered corpus listing whose\nnewest entries are what the fuzzer was working on when it stalled.\n\nAdd a one-minute heartbeat: `zig build` writes nothing until it finishes on a\nrunner, so a stalled job and a healthy one were indistinguishable for the\nwhole budget — #2040 burned 55 minutes of silence twice.\n\nThe report job gets a matching verdict, ordered ahead of the job-level\ntimeout, so an issue says which of the two happened and where to look.\n\nAlso record what the investigation ruled out, so a recurrence does not repeat\nit: no code regression (a local aarch64 A/B of the two commits is flat, the\nfailing one marginally faster, with the harness byte-identical), not corpus\nsize (x86_64 restored a larger one and ran fastest), not unit-suite growth,\nnot slow arm64 hardware (the gc-stress leg on the same run was normal), not a\nprinter cycle hang. And correct the matrix comment's headroom figure: one\nall-targets `--fuzz=200` pass measures ~13 min, not the \"~2 minute pass\" the\n2K limit was justified with.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the corpus claims: it is evicted nightly and never restored\n\nInvestigating #2040 mis-attributed a \"Cache Size: ~49 MB / restored\" line to\nthe fuzz corpus. It belongs to the setup-zig cache, which the corpus step's\noutput happens to follow. The corpus step's own line, on every arm64 default\nrun checked — six consecutive nightlies, including both the failing run and\nthe last green one — reads \"Cache not found for input keys:\nfuzz-corpus-arm64-default-\".\n\nSo the corpus has never once been restored. Saving works (an entry appears\nafter a green run), but ~365 KB touched once a day loses the repo's 10 GB LRU\nrace against the 100-400 MB setup-zig caches CI churns continuously. The\ncoverage-guided fuzzer has been running undirected, from an empty corpus,\nevery night — the workflow comment and the runbook both claimed the opposite.\n\nFor #2040 this settles one thing and unsettles another: the accumulated\ncorpus cannot explain the arm64 overrun, because both runs had none, which\nremoves the last standing hypothesis. A dispatched run on later main then\nfinished the same leg in 1826s, inside the historical band, so it does not\ncurrently reproduce. What is left is transient runner environment — recorded\nas such, not as a conclusion.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T20:03:21+05:30",
          "tree_id": "72bf0c75156055504cfc889a397a3ab441d51858",
          "url": "https://github.com/kaappi/kaappi/commit/5681053f9c173173264bb359f8cbf024f94f85f3"
        },
        "date": 1785606319631,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.262877,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.001142,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5898,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.979079,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046998,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313906,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057224,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.676322,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23042,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592305,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2795,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.774578,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.637088,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044365,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bf71d4b101cf79f57dc82066cfb48fecae3e6556",
          "message": "Drop the per-PR CHANGELOG gate; derive release notes from git log (#2103)\n\nThe gate required every PR touching src/ or lib/srfi/ to edit CHANGELOG.md.\nWith concurrent branches that is a guaranteed conflict: every PR appends to\nthe same few lines under [Unreleased], so each one that merges leaves the\nrest needing a rebase for a reason unrelated to their content.\n\nNothing depends on the job. release.yml still reads CHANGELOG.md when it\nbuilds the release body, and the release skill still writes that section at\nrelease time (Step 3) — only the per-PR requirement is gone.\n\nThe release skill's Step 2 is flipped to match: git log since the previous\ntag is now the primary source, with [Unreleased] folded in if it happens to\ncarry anything. It already consulted commits; it just called CHANGELOG.md\nprimary, which will now usually be empty. Added the actual command and a\nnote to read commit bodies rather than subjects, since this project's\nconvention puts the \"why\" there — which is what a release note needs.\n\nNote for the record: CLAUDE.md never carried this rule. Its only changelog\nmention is the /github-release skill description, which stays accurate.",
          "timestamp": "2026-08-01T20:08:40+05:30",
          "tree_id": "38cdd47d89df25052c5ecaf0948d0812a96acb8b",
          "url": "https://github.com/kaappi/kaappi/commit/bf71d4b101cf79f57dc82066cfb48fecae3e6556"
        },
        "date": 1785606340962,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.270543,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.486676,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.600473,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987644,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004704,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047095,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314682,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057345,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.835198,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.227023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596416,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.288053,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801133,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.537757,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044891,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7d81c3abeef6a3ded75c404012c5065f24c33424",
          "message": "Phase 2.7: SRFI-18 deep-copy matrix — 122 assertions, and FFI handles are aliased across heaps into a type-confused (0.0 . 0.0) (#2030)\n\n* Phase 2.7: enumerate the cross-heap deep-copy matrix\n\nThe SRFI-18 audit files test the procedures; nothing enumerated the type\nmatrix underneath them. gc_deep_copy.zig switches on all 41 ObjectTag\nmembers, and a tag that is neither on the refusal list nor round-trip\ntested is where a silent corruption lives.\n\nThis adds the enumeration: every reachable tag against all three copy\nboundaries (thread-start! capture, thread-join! result, and the uncaught\nexception path), for type AND content fidelity rather than mere arrival.\n\nThe 22 copied arms are correct. Comparison mode, parameter converters,\npromise forced-state, error irritants, exactness and internal sharing all\nsurvive both directions. The 13 reachable refusals are clean, and their\nshape is asymmetric in a way nothing pinned before: an IN refusal arrives\nwrapped in uncaught-exception?, an OUT refusal arrives direct.\n\nTwo cells were not covered by either class. ffi_library and ffi_function\nare *aliased* — the receiving heap gets a pointer into the sending one,\nwith no promotion, refcount or owner check. A child-created handle is\nreclaimed by the child's own collector while the receiver holds it and\narrives type-confused as (0.0 . 0.0), at all three boundaries including\nchannel-send with the child still running (#2027). The parent-owned\ncontrols are correct, which isolates the cliff to which heap allocates.\n\nNames are string literals throughout: SRFI 64 logs the test-name\nexpression as written, so a computed name records the string-append form\nand a remote-leg failure identifies no type at all.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.7, and record what the deep-copy matrix found\n\nThe unit's value was the enumeration itself: 22 copied arms verified for\ncontent fidelity, 13 refusals verified clean, and two tags in neither\nclass — the aliased FFI handles of #2027.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the class counts in the matrix header\n\nThe copied class is 24 arms, not 22: srfi18_time and random_source are\ncopied too. 22 is the reachable subset — flonum and native_closure are\nnot constructible from interpreted Scheme, which section G now states as\nthe reason rather than filing them under a fourth class that double-counts\nthem.\n\n24 + 3 + 14 = 41, matching ObjectTag exactly.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Say 22 of 24 in the tracker, matching the corrected header\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Add the guardian refusal rows the matrix was missing\n\nSection D covered 12 of the 13 reachable refused tags; guardian had only\nits IN direction tested, in Phase 5C's file. Both directions now asserted\nhere, so the refusal class is genuinely complete.\n\n122 assertions, green in ReleaseSafe and -Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* 122, not 120, after the guardian rows\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct a false claim about SRFI 64 test names\n\nThe header said SRFI 64 records the test-name *expression* as written, so a\ncomputed `string-append` name would log the form rather than the string.\nThat is not true. Checked directly:\n\n    (test-equal (string-append \"computed \" ty) 1 2)\n\nlogs `test-name: \"computed vector\"` — the evaluated string — in both the\nconsole output and the .log file.\n\nLeft as a correction rather than a deletion because the claim contradicts\nthe strategy doc's \"name every assertion\" footgun, which tells later units\nto derive names mechanically from the expression under test. If computed\nnames were broken that guidance would be wrong, and someone would have had\nto rediscover this.\n\nThe literal-per-row style stays; its actual justification is only that one\nrow per tag is greppable and cannot drift from the tag it names.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T20:11:23+05:30",
          "tree_id": "0a59238c2a79bb111c71466812b2aef3203cb782",
          "url": "https://github.com/kaappi/kaappi/commit/7d81c3abeef6a3ded75c404012c5065f24c33424"
        },
        "date": 1785606556281,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289563,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.629262,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597681,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018686,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005071,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048451,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057983,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.739126,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.242187,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.615899,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.291674,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.819703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682686,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044749,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}