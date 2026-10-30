#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral known-answer tests for the `sorbet` type checker CLI that mayhem/build.sh
# built with the project's normal flags (/mayhem/sorbet-oracle). Each case feeds a Ruby program and
# asserts Sorbet's exit status and the exact diagnostics / printed symbol table it must produce.
# Nothing is compiled here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

SORBET=/mayhem/sorbet-oracle
if [ ! -x "$SORBET" ]; then
  echo "missing $SORBET: mayhem/build.sh should have built it" >&2
  emit_ctrf "sorbet-cli" 0 1 0
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

passed=0; failed=0

# check <name> <expected-exit> <expected-substring>... -- reads the Ruby source on stdin, runs
# `sorbet [flags in $FLAGS] case.rb`, and requires the exit status and every substring in the output.
FLAGS=()
check() {
  local name="$1" want_rc="$2"; shift 2
  cat > "$WORK/case.rb"
  local out rc=0 ok=1
  out="$("$SORBET" --silence-dev-message "${FLAGS[@]}" "$WORK/case.rb" 2>&1)" || rc=$?
  if [ "$rc" -ne "$want_rc" ]; then
    ok=0; echo "FAIL $name: exit $rc, want $want_rc"
  fi
  local pat
  for pat in "$@"; do
    if ! grep -qF -- "$pat" <<<"$out"; then
      ok=0; echo "FAIL $name: output lacks: $pat"
    fi
  done
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1)); echo "ok   $name"
  else
    failed=$((failed + 1)); echo "---- output of $name:"; echo "$out" | head -40; echo "----"
  fi
}

check clean-program 0 "No errors! Great job." <<'EOF'
# typed: true
class A
  extend T::Sig
  sig { params(x: Integer).returns(Integer) }
  def double(x)
    x * 2
  end
end
EOF

check reveal-type-arith 100 "Revealed type: \`Integer\`" "srb.help/7014" "Errors: 1" <<'EOF'
# typed: true
T.reveal_type(1 + 2)
EOF

check reveal-type-string-concat 100 "Revealed type: \`String\`" "Errors: 1" <<'EOF'
# typed: true
T.reveal_type("a" + "b")
EOF

check reveal-type-nilable 100 "Revealed type: \`T.nilable(Integer)\`" <<'EOF'
# typed: true
extend T::Sig
sig { params(x: T.nilable(Integer)).void }
def f(x)
  T.reveal_type(x)
end
EOF

check sig-return-mismatch 100 \
  "Expected \`String\` but found \`Integer\` for method result type" "srb.help/7005" "Errors: 1" <<'EOF'
# typed: true
extend T::Sig

sig { params(x: Integer).returns(String) }
def f(x)
  x
end
EOF

check missing-method 100 "Method \`baz\` does not exist on \`Foo\`" "srb.help/7003" "Did you mean \`bar\`?" <<'EOF'
# typed: true
class Foo
  def bar
    1
  end
end
Foo.new.baz
EOF

check wrong-arity 100 "Too many arguments provided for method \`Foo#bar\`" "srb.help/7004" <<'EOF'
# typed: true
class Foo
  def bar(x)
    x
  end
end
Foo.new.bar(1, 2)
EOF

check syntax-error 100 "unexpected token \"end of file\"" "srb.help/2001" <<'EOF'
# typed: true
def f(
EOF

check uninitialized-constant 100 "Unable to resolve constant \`Nope\`" "srb.help/5002" <<'EOF'
# typed: true
Nope.new
EOF

check flow-sensitive-narrowing 0 "No errors! Great job." <<'EOF'
# typed: true
extend T::Sig
sig { params(x: T.nilable(Integer)).returns(Integer) }
def f(x)
  if x.nil?
    0
  else
    x + 1
  end
end
EOF

check strict-missing-sig 100 "does not have a \`sig\`" "srb.help/7017" <<'EOF'
# typed: strict
class A
  def x
    1
  end
end
EOF

FLAGS=(--print=symbol-table)
check symbol-table 0 \
  "class ::A < ::Object" "method ::A#x (<blk>) -> Integer" "method ::A#y (s, <blk>) -> String" <<'EOF'
# typed: strict
class A
  extend T::Sig
  sig { returns(Integer) }
  def x
    1
  end

  sig { params(s: String).returns(String) }
  def y(s)
    s
  end
end
EOF
FLAGS=()

emit_ctrf "sorbet-cli" "$passed" "$failed" 0
