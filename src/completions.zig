const std = @import("std");

// === kaappi completion scripts ===

const kaappi_bash =
    \\_kaappi() {
    \\    local cur prev
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\
    \\    case "$prev" in
    \\        --completions)
    \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
    \\            return ;;
    \\        --lib-path|-o|--profile-json|--coverage-xml)
    \\            COMPREPLY=($(compgen -f -- "$cur"))
    \\            return ;;
    \\        --timeout|--max-memory)
    \\            return ;;
    \\    esac
    \\
    \\    if [[ "$cur" == -* ]]; then
    \\        COMPREPLY=($(compgen -W "-h --help --version --lib-path --compile --emit-llvm -o --disassemble --sandbox --gc-stats --profile --profile-json --coverage --coverage-xml --timeout --max-memory --completions" -- "$cur"))
    \\        return
    \\    fi
    \\
    \\    local has_compile=false
    \\    for word in "${COMP_WORDS[@]}"; do
    \\        [[ "$word" == "compile" ]] && has_compile=true
    \\    done
    \\
    \\    if $has_compile; then
    \\        COMPREPLY=($(compgen -f -X '!*.scm' -- "$cur") $(compgen -W "-o" -- "$cur"))
    \\    else
    \\        COMPREPLY=($(compgen -W "compile" -- "$cur") $(compgen -f -X '!*.scm' -- "$cur"))
    \\    fi
    \\}
    \\complete -o filenames -F _kaappi kaappi
    \\
;

const kaappi_zsh =
    \\#compdef kaappi
    \\
    \\_kaappi() {
    \\    local -a flags
    \\    flags=(
    \\        '-h[Show help message]'
    \\        '--help[Show help message]'
    \\        '--version[Show version]'
    \\        '--lib-path[Add library search path]:path:_files -/'
    \\        '--compile[Compile file to bytecode (.sbc)]'
    \\        '--emit-llvm[Emit LLVM IR text (.ll)]'
    \\        '-o[Output path]:file:_files'
    \\        '--disassemble[Disassemble bytecode]'
    \\        '--sandbox[Restrict filesystem and process access]'
    \\        '--gc-stats[Print GC statistics on exit]'
    \\        '--profile[Enable profiling]'
    \\        '--profile-json[Write profile JSON to file]:file:_files'
    \\        '--coverage[Report library procedure coverage]'
    \\        '--coverage-xml[Write Cobertura XML coverage to file]:file:_files'
    \\        '--timeout[Execution timeout in milliseconds]:ms:'
    \\        '--max-memory[Maximum heap memory in bytes]:bytes:'
    \\        '--completions[Output shell completion script]:shell:(bash zsh fish)'
    \\    )
    \\
    \\    _arguments -s \
    \\        $flags \
    \\        '1:command or file:_files -g "*.scm"' \
    \\        '*:script args:_files'
    \\}
    \\
    \\_kaappi "$@"
    \\
;

const kaappi_fish =
    \\# Completions for kaappi
    \\complete -c kaappi -l help -s h -d 'Show help message'
    \\complete -c kaappi -l version -d 'Show version'
    \\complete -c kaappi -l lib-path -r -F -d 'Add library search path'
    \\complete -c kaappi -l compile -d 'Compile file to bytecode (.sbc)'
    \\complete -c kaappi -l emit-llvm -d 'Emit LLVM IR text (.ll)'
    \\complete -c kaappi -s o -r -F -d 'Output path'
    \\complete -c kaappi -l disassemble -d 'Disassemble bytecode'
    \\complete -c kaappi -l sandbox -d 'Restrict filesystem and process access'
    \\complete -c kaappi -l gc-stats -d 'Print GC statistics on exit'
    \\complete -c kaappi -l profile -d 'Enable profiling'
    \\complete -c kaappi -l profile-json -r -F -d 'Write profile JSON to file'
    \\complete -c kaappi -l coverage -d 'Report library procedure coverage'
    \\complete -c kaappi -l coverage-xml -r -F -d 'Write Cobertura XML coverage to file'
    \\complete -c kaappi -l timeout -r -x -d 'Execution timeout in milliseconds'
    \\complete -c kaappi -l max-memory -r -x -d 'Maximum heap memory in bytes'
    \\complete -c kaappi -l completions -r -x -a 'bash zsh fish' -d 'Output shell completion script'
    \\complete -c kaappi -a compile -d 'Compile to native binary via LLVM'
    \\
;

// === thottam completion scripts ===

const thottam_bash =
    \\_thottam() {
    \\    local cur prev
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\
    \\    case "$prev" in
    \\        --completions)
    \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
    \\            return ;;
    \\    esac
    \\
    \\    if [[ "$cur" == -* ]]; then
    \\        COMPREPLY=($(compgen -W "--locked -h --help --version --completions" -- "$cur"))
    \\        return
    \\    fi
    \\
    \\    local subcmd=""
    \\    for word in "${COMP_WORDS[@]:1}"; do
    \\        case "$word" in
    \\            install|remove|list|update|verify) subcmd="$word"; break ;;
    \\        esac
    \\    done
    \\
    \\    if [[ -z "$subcmd" ]]; then
    \\        COMPREPLY=($(compgen -W "install remove list update verify" -- "$cur"))
    \\    fi
    \\}
    \\complete -F _thottam thottam
    \\
;

const thottam_zsh =
    \\#compdef thottam
    \\
    \\_thottam() {
    \\    local -a subcmds
    \\    subcmds=(
    \\        'install:Install a package'
    \\        'remove:Remove a package'
    \\        'list:List installed packages'
    \\        'update:Update one or all packages'
    \\        'verify:Check installs match the lockfile'
    \\    )
    \\
    \\    _arguments -s \
    \\        '--locked[Refuse to install packages not in the lockfile]' \
    \\        '-h[Show help message]' \
    \\        '--help[Show help message]' \
    \\        '--version[Show version]' \
    \\        '--completions[Output shell completion script]:shell:(bash zsh fish)' \
    \\        '1:command:->subcmd' \
    \\        '*:argument:' \
    \\    && return
    \\
    \\    case "$state" in
    \\        subcmd)
    \\            _describe 'command' subcmds ;;
    \\    esac
    \\}
    \\
    \\_thottam "$@"
    \\
;

const thottam_fish =
    \\# Completions for thottam
    \\complete -c thottam -f
    \\complete -c thottam -l locked -d 'Refuse to install packages not in the lockfile'
    \\complete -c thottam -l help -s h -d 'Show help message'
    \\complete -c thottam -l version -d 'Show version'
    \\complete -c thottam -l completions -r -x -a 'bash zsh fish' -d 'Output shell completion script'
    \\complete -c thottam -a install -d 'Install a package'
    \\complete -c thottam -a remove -d 'Remove a package'
    \\complete -c thottam -a list -d 'List installed packages'
    \\complete -c thottam -a update -d 'Update one or all packages'
    \\complete -c thottam -a verify -d 'Check installs match the lockfile'
    \\
;

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
