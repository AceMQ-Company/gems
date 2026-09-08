#!/usr/bin/env bash
#
# Adds gems to the feed and regenerates its index.
#
#   ./scripts/publish.sh path/to/acemq-amqp-0.2.0.gem [...]
#   ./scripts/publish.sh                 # regenerate the index only
#
# There is no server and no credentials: the feed is a directory a RubyGems
# client walks by convention, exactly as the Maven repository and the NuGet feed
# beside it are. To publish, run this and commit the result.
#
# `gem generate_index` writes both index formats, which is worth knowing because
# it sounds like it should not: the compact index (versions, info/<gem>, names)
# is normally built on demand by rubygems.org from a database, so the obvious
# assumption is that a static directory can only offer the classic
# specs.4.8.gz. It is plain text, it is written to disk here, and current
# Bundler and RubyGems read it first. The classic index is generated alongside
# it for older clients.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v gem >/dev/null || { echo "rubygems is required to build the index" >&2; exit 1; }

mkdir -p gems

for gem in "$@"; do
  [ -f "$gem" ] || { echo "no such gem: $gem" >&2; exit 1; }
  case "$gem" in
    *.gem) ;;
    *) echo "not a gem: $gem" >&2; exit 1 ;;
  esac
  name="$(basename "$gem")"
  # A published version keeps the bytes it was published with. People have
  # already resolved and locked it, and replacing it in place means two machines
  # hold different code under one version and neither of them is wrong.
  #
  # Kept rather than refused, because a release job has to be re-runnable and a
  # gem is not byte-reproducible: the gemspec carries a build date, so a rebuild
  # of the very same commit differs from what is on the feed. Failing here would
  # mean no release could ever be re-run, and the failure would look like
  # tampering when it is only a second `gem build`. Publishing a genuinely
  # changed version needs a new version number, which is the same rule every
  # immutable registry enforces.
  if [ -f "gems/$name" ]; then
    if cmp -s "$gem" "gems/$name"; then
      echo "  $name is already published, byte for byte"
    else
      echo "  $name is already published; keeping the published bytes"
      echo "  (a rebuild differs by its timestamp; publish a new version to change the code)"
    fi
  else
    cp "$gem" "gems/$name"
    echo "  added $name"
  fi
done

# --directory . rather than a temporary tree, so the index describes everything
# already published and not only what this run happened to add.
gem generate_index --directory . >/dev/null
count=$(ls gems/*.gem 2>/dev/null | wc -l | tr -d ' ')
echo "  index regenerated over $count gem(s)"

# Whether the compact index was written at all depends on the RubyGems doing the
# writing: older ones emit only the classic index and leave versions/info/names
# untouched. That is the dangerous case, because a *stale* compact index is far
# worse than a missing one -- a current client reads /versions, does not find the
# gem listed, and stops. It never looks at the classic index, so a feed that is
# perfectly correct in the old format reports "Could not find a valid gem".
#
# So: if the compact index does not describe what the classic index describes,
# delete it. A client that gets a 404 for /versions falls back and resolves; a
# client that gets an empty one gives up.
#
# The comparison is against specs.4.8.gz rather than against the filenames in
# gems/, because a gem's name comes from the gemspec inside it and not from what
# the file happens to be called. Reading the filename gets that wrong for any
# gem saved under a different name, and then this check reports a healthy feed
# as broken -- which it did, the first time it ran.
classic_names=$(ruby -rzlib -e '
  begin
    specs = Marshal.load(Zlib::GzipReader.open("specs.4.8.gz").read)
    puts specs.map { |name, _, _| name }.uniq.sort.join("\n")
  rescue StandardError
  end
')

stale=0
if [ -n "$classic_names" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ ! -s versions ] || ! grep -q "^$name " versions; then
      stale=1
      break
    fi
  done <<EOF
$classic_names
EOF
fi

if [ -n "$classic_names" ] && [ "$stale" = 1 ]; then
  rm -rf versions names info
  echo "  this rubygems ($(gem --version)) did not write the compact index;"
  echo "  removed it so clients fall back to the classic one rather than reading an empty index"
elif [ -n "$classic_names" ]; then
  echo "  compact index lists $(printf '%s\n' "$classic_names" | wc -l | tr -d ' ') gem(s)"
fi

# The landing page's table, rebuilt from what is on disk rather than appended
# to, so a gem removed by hand disappears from it too.
python3 - <<'PY'
import glob, html, os, re
from collections import defaultdict

gems = defaultdict(list)
for path in sorted(glob.glob("gems/*.gem")):
    stem = os.path.basename(path)[:-4]
    # name-1.2.3 / name-1.2.3-java / name-1.2.3.pre.1 -- split at the last
    # hyphen that is followed by a digit, which is where RubyGems splits it.
    m = re.match(r"^(.*?)-(\d[^-]*(?:-[A-Za-z][\w]*)?)$", stem)
    if not m:
        continue
    gems[m.group(1)].append(m.group(2))

if gems:
    rows = []
    for name in sorted(gems):
        versions = sorted(set(gems[name]), key=lambda v: [
            int(p) if p.isdigit() else p for p in re.split(r"[.-]", v)])
        rows.append("    <tr><td><code>%s</code></td><td>%s</td></tr>" % (
            html.escape(name), ", ".join(html.escape(v) for v in versions)))
    body = "\n".join(rows)
else:
    body = '    <tr><td colspan="2" class="no">Nothing published yet.</td></tr>'

table = ("  <table>\n"
         "    <tr><th>Gem</th><th>Versions</th></tr>\n"
         f"{body}\n"
         "  </table>")

page = open("index.html", encoding="utf-8").read()
start = "<!-- gems:start -- written by scripts/publish.sh; do not edit by hand -->"
end = "<!-- gems:end -->"
before, _, rest = page.partition(start)
_, _, after = rest.partition(end)
open("index.html", "w", encoding="utf-8").write(
    f"{before}{start}\n{table}\n  {end}{after}")
print("  landing page lists %d gem(s)" % len(gems))
PY

# Jekyll would otherwise refuse to serve anything under a directory whose name
# begins with an underscore, and skip the dot-prefixed files entirely.
touch .nojekyll
