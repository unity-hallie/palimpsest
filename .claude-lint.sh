#!/usr/bin/env bash
# .claude-lint.sh — palimpsest repo linter
# Called by ~/.claude/hooks/post-write-lint.sh with the written file path as $1.

FILEPATH="$1"

case "$FILEPATH" in
    *.glsl)
        if command -v glslangValidator &>/dev/null; then
            REPO_ROOT=$(git -C "$(dirname "$FILEPATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILEPATH")
            PREAMBLE="$REPO_ROOT/.glsl-preamble.glsl"
            if [ -f "$PREAMBLE" ]; then
                TMPFILE=$(mktemp /tmp/lint-XXXXXX.frag)
                { echo "#version 330"; cat "$PREAMBLE" "$FILEPATH"; } > "$TMPFILE"
                glslangValidator -S frag "$TMPFILE"
                STATUS=$?
                rm -f "$TMPFILE"
                exit $STATUS
            else
                glslangValidator -S frag -d "$FILEPATH"
            fi
        else
            echo "⚠ glslangValidator not found — install with: brew install glslang" >&2
            echo "  Skipping lint for: $FILEPATH" >&2
        fi
        ;;
esac
