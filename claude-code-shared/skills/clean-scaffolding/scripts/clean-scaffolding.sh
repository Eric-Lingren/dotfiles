#!/usr/bin/env bash
# Usage: clean-scaffolding.sh preview|delete
#
# preview: enumerate disposable doc scaffolding, print the full grouped file
#          list and a total. Exit 0 if files were found, exit 2 if nothing to
#          clean. The total is derived from the same pass that prints the list,
#          so a count can never exist without the list having been printed.
# delete:  re-enumerate the same set, remove each explicit path (printing each
#          one as it goes), then rmdir any now-empty scaffolding dirs.
#
# Scope (relative to cwd):
#   docs/seeds/    all files
#   docs/prd/      all files
#   docs/tasks/    all files
#   docs/handoffs/ *.md files only
# Never touches docs/adr/ or docs/prototypes/. Never runs git. Never edits
# .gitignore. Deletion uses an explicit rm per path: no rm -f, no bare rm *,
# no find -delete.
#
# Written for bash 3.2 (stock macOS): no mapfile, no associative arrays.
set -euo pipefail

DIRS="docs/seeds docs/prd docs/tasks docs/handoffs"

list_dir() {
  case "$1" in
    docs/seeds)    find docs/seeds    -maxdepth 1 -type f               2>/dev/null ;;
    docs/prd)      find docs/prd      -maxdepth 1 -type f               2>/dev/null ;;
    docs/tasks)    find docs/tasks    -maxdepth 1 -type f               2>/dev/null ;;
    docs/handoffs) find docs/handoffs -maxdepth 1 -name '*.md' -type f  2>/dev/null ;;
  esac
}

enumerate() {
  for d in $DIRS; do list_dir "$d"; done
}

preview() {
  if [ -z "$(enumerate)" ]; then
    echo "Nothing to clean."
    return 2
  fi
  echo "About to delete:"
  echo
  total=0
  for d in $DIRS; do
    files=$(list_dir "$d")
    [ -z "$files" ] && continue
    echo "  ${d}/"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      echo "    ${f##*/}"
      total=$((total + 1))
    done <<EOF
$files
EOF
    echo
  done
  printf "Total: %d files\n" "$total"
  return 0
}

do_delete() {
  total=0
  for d in $DIRS; do
    files=$(list_dir "$d")
    [ -z "$files" ] && continue
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if rm "$f" 2>/dev/null; then
        echo "removed $f"
        total=$((total + 1))
      else
        echo "skipped (could not remove) $f" >&2
      fi
    done <<EOF
$files
EOF
  done
  rmdir docs/seeds docs/prd docs/tasks docs/handoffs docs 2>/dev/null || true
  printf "Deleted %d files.\n" "$total"
}

do_delete_files() {
  # Delete a specific list of files passed as remaining arguments.
  # Used by the lineage-aware path after the skill validates chain completeness
  # and ADR coverage. The caller must pass at least one file path.
  total=0
  for f in "$@"; do
    if [ -f "$f" ]; then
      if rm "$f" 2>/dev/null; then
        echo "removed $f"
        total=$((total + 1))
      else
        echo "skipped (could not remove) $f" >&2
      fi
    else
      echo "skipped (not found) $f" >&2
    fi
  done
  # Remove any now-empty scaffolding dirs
  rmdir docs/seeds docs/prd docs/tasks docs/handoffs docs 2>/dev/null || true
  printf "Deleted %d files.\n" "$total"
}

case "${1:-}" in
  preview)
    if preview; then exit 0; else exit 2; fi
    ;;
  delete)
    do_delete
    ;;
  delete-files)
    shift  # drop "delete-files" from args
    if [ $# -eq 0 ]; then
      echo "Usage: clean-scaffolding.sh delete-files <file...>" >&2
      exit 1
    fi
    do_delete_files "$@"
    ;;
  *)
    echo "Usage: clean-scaffolding.sh preview|delete|delete-files <file...>" >&2
    exit 1
    ;;
esac
