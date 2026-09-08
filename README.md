# AceMQ gem feed

A static RubyGems source. No account, no credentials, no server: a directory of
`.gem` files and the index that describes them, served over HTTPS by GitHub
Pages at <https://acemq.org/gems/>.

It exists because the AceMQ Ruby library is not on rubygems.org yet. A gem name
there is permanent and a pushed version cannot really be taken back, so the
library is published here until it is ready for that decision to be irreversible.

## Using it

```ruby
# Gemfile
source "https://rubygems.org"

source "https://acemq.org/gems" do
  gem "acemq-amqp"
end
```

A block rather than a second top-level `source`, so only the gems named inside
it are looked for here. Two open-ended sources make resolution ambiguous, and
Bundler warns about exactly that.

Without Bundler:

```bash
gem install acemq-amqp --source https://acemq.org/gems/
```

## Publishing

```bash
./scripts/publish.sh path/to/acemq-amqp-0.2.0.gem
git add -A && git commit -m "Publish acemq-amqp 0.2.0" && git push
```

The AceMQ Ruby release workflow does this for you on a tag. Running it by hand
is for repairing the index, not for routine publishing.

The script refuses to replace an existing `.gem` with different bytes. A version
someone has already resolved and locked must keep the contents it had, or two
machines end up running different code under one version number and neither of
them is wrong.

## The index

Both formats, and `gem generate_index` writes both without being asked.

The **compact index** — `versions`, `info/<gem>`, `names` — is what current
Bundler and RubyGems reach for first, and it is plain text a directory can serve
as-is. That is worth stating because it is easy to assume otherwise: the compact
index is normally produced on demand by rubygems.org from a database, which
makes it sound like something a static feed cannot have. It is not.

The **classic index** — `specs.4.8.gz`, `latest_specs.4.8.gz`,
`prerelease_specs.4.8.gz`, `quick/Marshal.4.8/` — sits alongside it for older
clients.

## Layout

```
gems/                       the .gem files themselves
versions                    compact index: every gem and its versions
info/<gem>                  compact index: versions, dependencies, checksums
names                       compact index: the gem names
quick/Marshal.4.8/          classic: one marshalled gemspec per gem
specs.4.8.gz                classic: every version of every gem
latest_specs.4.8.gz         classic: the newest version of each
prerelease_specs.4.8.gz     classic: prereleases, kept separate
scripts/publish.sh          adds a gem and regenerates all of the above
```

Everything here is generated except `scripts/`, this README and the landing
page. Deleting the index and re-running `./scripts/publish.sh` rebuilds it from
the gems on disk.

## Licence

The gems carry their own licences. This repository — the scripts and the page —
is Apache-2.0, like the libraries it serves.
