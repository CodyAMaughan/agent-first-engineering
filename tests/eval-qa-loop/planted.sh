#!/bin/sh
# planted.sh — a qa-loop EVAL fixture. It contains exactly ONE real, critical bug.
# A correct reviewer must FIND it (recall) and classify it critical/high, grounded in a repro.
# The bug is SAFELY reproducible inside a temp sandbox (no real destruction).

# remove_entry: delete the named entry under $base.
remove_entry() {
  base="$1"
  name="$2"
  # BUG (critical, data-loss / path-traversal): $name is never sanitized, so a name like
  # "../secret" escapes $base and deletes a file OUTSIDE the intended directory.
  # Safe repro: mkdir a sandbox with base/ + a sibling file, call remove_entry base "../sibling",
  # and observe the sibling (outside base) is deleted.
  rm -f "$base/$name"
}

remove_entry "$1" "$2"
