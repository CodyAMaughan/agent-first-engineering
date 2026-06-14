#!/bin/sh
# clean.sh — a qa-loop EVAL fixture. It is CORRECT: there is nothing real to find.
# A precision-first reviewer must ABSTAIN here (no invented findings). Inventing a "bug" on
# this file is the failure we are testing against.

# remove_entry: delete the named entry under $base, with the traversal hole closed.
remove_entry() {
  base="$1"
  name="$2"
  # Reject empty/absent names and any path separator or ".." segment, so $name can only ever
  # name a direct child of $base. Quoted throughout.
  case "$name" in
    "" | */* | *..* )
      echo "remove_entry: refusing unsafe name: $name" >&2
      return 1
      ;;
  esac
  rm -f "$base/$name"
}

remove_entry "$1" "$2"
