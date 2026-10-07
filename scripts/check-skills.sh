#!/usr/bin/env bash
# Checks the skills this repo publishes.
#
# People install these with `npx skills add sofiandreoli/wop-skills`, which reads the frontmatter and
# copies the skill directory. Nothing validates that content on the way out, and the failures are
# quiet: a skill with no description is never loaded on its own, a `name` that disagrees with its
# directory installs under one name and announces itself as another, and a broken `references/` link
# just means the skill works without the file it was told to read. None of that errors — it degrades.
# So it gets checked here instead.
set -euo pipefail

cd "$(dirname "$0")/.."
command -v ruby >/dev/null || { echo "ruby not found" >&2; exit 1; }

fail() {
	echo "check-skills: $1" >&2
	exit 1
}

[ -d skills ] || fail "skills/ is missing"

found_skill=""
for dir in skills/*/; do
	[ -d "$dir" ] || continue
	found_skill="yes"
	name="$(basename "$dir")"
	skill="$dir/SKILL.md"
	[ -f "$skill" ] || fail "$name has no SKILL.md"
	ruby -ryaml -e '
	  name, path = ARGV
	  text = File.read(path)
	  unless text.start_with?("---\n") && (close = text.index("\n---\n", 3))
	    abort("check-skills: #{name}/SKILL.md has no YAML frontmatter")
	  end
	  front = begin
	    YAML.safe_load(text[4...close + 1]) || {}
	  rescue Psych::SyntaxError => e
	    abort("check-skills: #{name}/SKILL.md frontmatter is not valid YAML: #{e.message}")
	  end
	  if front["description"].to_s.strip.empty?
	    abort("check-skills: #{name}/SKILL.md has no description, so Claude cannot discover it")
	  end
	  unless front["name"] == name
	    abort("check-skills: #{name}/SKILL.md sets name #{front["name"].inspect}, which does not match its directory")
	  end
	' "$name" "$skill"
done
[ -n "$found_skill" ] || fail "skills/ has no skills"

# These skills used to ship as a Claude Code plugin, where they were invoked as `/wop:audit`. That
# syntax does not exist for a skill installed on its own, so a leftover reference tells the reader to
# type something that does nothing. The one exception is the configure skill, which still reads the
# old heading out of reports written before the rename.
stray="$(grep -rn 'wop:audit\|wop:configure\|wop:use' skills/ |
	grep -v '^skills/wop-configure/SKILL.md:' || true)"
if [ -n "$stray" ]; then
	echo "check-skills: plugin-era /wop: references survived the rename:" >&2
	printf '%s\n' "$stray" >&2
	exit 1
fi

# Every references/ and assets/ path a SKILL.md names has to exist. A missing one is silent: the skill
# simply proceeds without the file.
missing=""
for skill in skills/*/SKILL.md; do
	dir="$(dirname "$skill")"
	for path in $(grep -o '\(references\|assets\)/[A-Za-z0-9._-]*\.md' "$skill" | sort -u); do
		[ -f "$dir/$path" ] || missing="$(printf '%s\n  %s -> %s' "$missing" "$skill" "$path")"
	done
done
if [ -n "$missing" ]; then
	echo "check-skills: SKILL.md files point at files that do not exist:$missing" >&2
	exit 1
fi

echo "check-skills: ok"
