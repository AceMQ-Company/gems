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
  # Refused rather than overwritten. A published version is something people
  # have already resolved and locked; replacing its bytes in place means two
  # machines can hold different code under one version and neither is wrong.
  if [ -f "gems/$name" ] && ! cmp -s "$gem" "gems/$name"; then
    echo "refusing to replace gems/$name with different bytes; yank and republish under a new version" >&2
    exit 1
  fi
  cp "$gem" "gems/$name"
  echo "  added $name"
done

# --directory . rather than a temporary tree, so the index describes everything
# already published and not only what this run happened to add.
gem generate_index --directory . >/dev/null
echo "  index regenerated over $(ls gems/*.gem 2>/dev/null | wc -l | tr -d ' ') gem(s)"

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
