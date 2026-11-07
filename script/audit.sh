#!/usr/bin/env bash
#
# Run `brew audit --strict` over every formula in the tap and fail on every
# problem except the one upstream rule that contradicts this tap's design.
#
# Upstream Homebrew (commit 85ffa721b0, "Require verifiable official formula
# sources", 2026-10-17) added this rule to ResourceAuditor:
#
#   if (using == :git || url_strategy == GitDownloadStrategy) && specs[:tag] && !specs[:revision]
#     problem "Git should specify `revision:` when a `tag:` is specified."
#   elsif !version&.head? && DownloadStrategyDetector.detect(url!, using) <= GitDownloadStrategy &&
#         !specs[:revision].to_s.match?(/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i)
#     problem "Git should specify a full commit hash in `revision:`."
#   end
#
# The second branch fires for every Git source that is not pinned to a commit
# hash, unless the spec's version is HEAD -- which is how upstream spells
# "this formula tracks a moving branch". This tap tracks moving branches on
# purpose (see AGENTS.md, "Sources are branches, not revisions"), so the rule
# reports one problem per formula and nothing else.
#
# The rule cannot be satisfied without changing what this tap is. Pinning a
# `revision:` would freeze the sources, which is the opposite of the design.
# Using `version "HEAD"` would make Homebrew treat the installed keg as a HEAD
# keg, and `brew outdated` and `brew upgrade` skip HEAD kegs entirely -- the
# branch would stop moving for users, and the published bottle names would
# change from "<formula>-<version>.<tag>.bottle.tar.gz" to
# "<formula>-HEAD.<tag>.bottle.tar.gz". So the rule is tolerated here, but
# only that one rule, and only for formulae that really do track a branch.
#
# The tolerance is narrow on purpose:
#
#   * Every other audit problem fails the job -- including the other rules in
#     the same audit method ("Git should specify `revision:` when a `tag:` is
#     specified.", "Redundant `using:` value in URL", the CVS rules) and every
#     rule in the other audit methods.
#   * The tolerated problem must be reported exactly once for a formula that
#     tracks a branch, and not at all for one that does not -- as long as the
#     Homebrew running the audit has the rule at all. If upstream relaxes or
#     renames the rule, this check fails and asks for an update instead of
#     silently keeping an exemption nobody needs any more.
#   * The expectation is derived from each formula itself -- a stable spec
#     with a `branch:`, no `revision:` and a non-HEAD version -- rather than
#     from a hard-coded list of formula names, so a new formula is covered
#     without editing this script.
#
# The rule only exists in Homebrew master (it is in no release tag yet), so
# the Homebrew this script runs under may not have it: a CI runner's
# Homebrew is often older than the local one. The rule's presence is
# therefore DETECTED rather than assumed:
#
#   * The probe asks Homebrew's own auditor about a synthetic Git resource
#     that tracks a branch -- the same question the rule answers. If the
#     auditor reports the problem, the rule exists here.
#   * The source of `audit_download_strategy` is read as well. If the rule's
#     text is there but the probe did not fire, upstream changed the rule's
#     shape and this script must be updated -- that is a failure, not a
#     reason to expect nothing.
#   * Homebrew's own git history says whether the commit that introduced the
#     rule is part of this Homebrew. If it is, and the rule is gone, the
#     exemption is no longer needed -- also a failure, so it cannot rot.
#   * A Homebrew that simply predates the rule is not a failure: the
#     exemption is inert there, the expectation drops to zero tolerated
#     problems, and everything else is still audited.
#   * A probe that could not run at all is a failure too. It must not be
#     read as "the rule is not there", because that would silently drop the
#     exemption.
#
# `brew audit` prints its problem lines on stdout and its summary on stderr.
# In GitHub Actions it also prints the same problems as workflow annotations;
# GITHUB_ACTIONS is cleared for the audit so that the output is one
# predictable list of problem lines. Real problems are reported as workflow
# annotations by this script instead, so they still show up against the
# formula file.

set -euo pipefail

tap="${1:-milesbuckton/qemu-virgl}"
tap_dir="$(brew --repository "${tap}")"
brew_repository="$(brew --repository)"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# The tolerated problem, verbatim. Homebrew prefixes the spec name
# ("Stable: ") to the auditor's own message. The backticks are literal, so the
# text is read from a quoted heredoc rather than assigned in single quotes.
IFS= read -r tolerated_message <<'EOF'
Stable: Git should specify a full commit hash in `revision:`.
EOF
tolerated_suffix="* ${tolerated_message}"

# The upstream commit that introduced the rule. Used to tell a Homebrew that
# predates the rule (the exemption is inert, nothing to expect) apart from a
# Homebrew where upstream has since removed it (the exemption has rotted and
# must be dropped).
rule_commit="85ffa721b04d2aed23b4badb3ddbac6ae8322232"

# Two questions for Homebrew itself, asked with brew ruby so that they are
# answered by the Homebrew that will run the audit:
#
#   "modes" -- how does each formula pin its source?
#       "branch" -- a stable spec with a `branch:`, no `revision:` and a
#                   version that is not HEAD: the shape this tap uses on
#                   purpose, and the only shape for which the tolerated
#                   problem is expected.
#       "pinned" -- anything else (a tag, a revision, a HEAD version, or no
#                   stable spec at all), where the tolerated problem must not
#                   appear: a rule that fires there is a genuine problem.
#       `specs` is the URL options hash ("branch:", "tag:", "revision:"),
#       which is what Homebrew's own auditor reads.
#
#   "probe" -- does this Homebrew have the rule?
#       The probe is the rule itself, applied to a synthetic Git resource
#       that tracks a branch, through Homebrew's own auditor. The synthetic
#       resource is never downloaded: the auditor only looks at the URL and
#       the specs.
cat >"${work_dir}/helpers.rb" <<'RUBY'
require "formulary"

case ARGV[0]
when "modes"
  Dir[File.join(ARGV.fetch(1), "Formula", "*.rb")].sort.each do |path|
    formula = Formulary.factory(path)
    spec = formula.stable
    specs = spec&.specs || {}
    tracking = !spec.nil? && !specs[:branch].nil? && specs[:revision].nil? &&
               !(spec.version&.head?) && !formula.head_only?
    puts [File.basename(path, ".rb"), tracking ? "branch" : "pinned"].join("\t")
  end
when "probe"
  message = "Git should specify a full commit hash in `revision:`."
  in_source = false
  fires = false
  error = ""
  file = nil
  begin
    require "resource_auditor"
    file = Homebrew::ResourceAuditor.instance_method(:audit_download_strategy).source_location&.first
    in_source = !file.nil? && File.exist?(file) && File.read(file).include?(message)
  rescue StandardError, ScriptError => e
    error = "could not read the auditor's source: #{e.class}: #{e.message}"
  end
  unless error.empty?
    puts "rule_in_source\t#{in_source}"
    puts "rule_fires\t#{fires}"
    puts "probe_error\t#{error}"
    exit
  end
  begin
    require "resource"
    resource = Resource.new("audit-rule-probe")
    resource.url("https://example.invalid/audit-rule-probe.git", branch: "main")
    resource.version("1.0")
    auditor = Homebrew::ResourceAuditor.new(resource, :stable, only: ["download_strategy"]).audit
    fires = auditor.problems.any? { |problem| problem.include?(message) }
  rescue StandardError, ScriptError => e
    error = "#{e.class}: #{e.message}"
  end
  puts "rule_in_source\t#{in_source}"
  puts "rule_fires\t#{fires}"
  puts "probe_error\t#{error}"
end
RUBY

expectations="$(brew ruby "${work_dir}/helpers.rb" modes "${tap_dir}")"

probe_output="$(brew ruby "${work_dir}/helpers.rb" probe 2>/dev/null || true)"
rule_fires="$(printf '%s\n' "${probe_output}" | awk -F'\t' '$1 == "rule_fires" { print $2; exit }')"
rule_in_source="$(printf '%s\n' "${probe_output}" | awk -F'\t' '$1 == "rule_in_source" { print $2; exit }')"
probe_error="$(printf '%s\n' "${probe_output}" | awk -F'\t' '$1 == "probe_error" { print $2; exit }')"
rule_fires="${rule_fires:-false}"
rule_in_source="${rule_in_source:-false}"

# Does this Homebrew contain the commit that introduced the rule? "yes" means
# the rule was here at some point, "no" means this Homebrew predates it, and
# "unknown" means the history is not available (a shallow or non-git
# install) and nothing can be concluded.
rule_known="unknown"
if git -C "${brew_repository}" cat-file -e "${rule_commit}^{commit}" 2>/dev/null
then
  if git -C "${brew_repository}" merge-base --is-ancestor "${rule_commit}" HEAD 2>/dev/null
  then
    rule_known="yes"
  else
    rule_known="no"
  fi
fi

# The path GitHub should attach an annotation to. brew's own annotations use
# the workspace-relative path; do the same so the annotation lands on the
# formula file in the diff view.
annotation_path() {
  local path=$1
  if [[ -n "${GITHUB_WORKSPACE:-}" ]] && [[ "${path}" == "${GITHUB_WORKSPACE}/"* ]]
  then
    printf '%s' "${path#"${GITHUB_WORKSPACE}/"}"
  else
    printf '%s' "${path}"
  fi
}

rc=0
audited=0

# What is this Homebrew's relationship to the rule?
#
#   "present"  -- the rule is here and fires. The tolerated problem is
#                 expected exactly once for a formula that tracks a branch.
#   "changed"  -- the rule is in this Homebrew's source but does not fire:
#                 upstream changed its shape. The script must be updated.
#   "removed"  -- this Homebrew once had the rule and no longer does: the
#                 exemption has rotted and must be dropped.
#   "absent"   -- this Homebrew predates the rule. The exemption is inert
#                 and nothing is expected; every other rule still applies.
rule_state="absent"
if [[ -n "${probe_error}" ]]
then
  # The probe could not run at all. That is a problem with THIS script or with
  # this Homebrew, not with the tap, and it must not be mistaken for "the rule
  # is not there" -- that would silently drop the exemption.
  rule_state="broken"
elif [[ "${rule_fires}" == "true" ]]
then
  rule_state="present"
elif [[ "${rule_in_source}" == "true" ]]
then
  rule_state="changed"
elif [[ "${rule_known}" == "yes" ]]
then
  rule_state="removed"
fi

case "${rule_state}" in
  present)
    ;;
  broken)
    echo "::error::could not probe this Homebrew for the 'full commit hash in" \
      "revision' rule: ${probe_error} -- update script/audit.sh"
    rc=1
    ;;
  changed)
    echo "::error::the 'full commit hash in revision' rule is in this Homebrew's" \
      "source but did not fire; upstream changed its shape -- update script/audit.sh"
    rc=1
    ;;
  removed)
    echo "::error::this Homebrew contains the commit that introduced the" \
      "'full commit hash in revision' rule, but the rule is gone; the exemption" \
      "is no longer needed -- update script/audit.sh"
    rc=1
    ;;
  absent)
    echo "::warning::this Homebrew does not have the 'full commit hash in" \
      "revision' rule (it predates it); the exemption is inert here and no" \
      "tolerated problem is expected"
    ;;
  *)
    echo "::error::unknown rule state '${rule_state}' -- update script/audit.sh"
    rc=1
    ;;
esac

for formula in "${tap_dir}"/Formula/*.rb
do
  name="$(basename "${formula}" .rb)"
  fq="${tap}/${name}"
  audited=$((audited + 1))
  echo "=== auditing ${fq} ==="

  mode="$(printf '%s\n' "${expectations}" | awk -F'\t' -v n="${name}" '$1 == n { print $2; exit }')"
  if [[ -z "${mode}" ]]
  then
    echo "::error::${fq}: could not determine how this formula pins its source"
    rc=1
    continue
  fi

  stdout_file="${work_dir}/${name}.out"
  stderr_file="${work_dir}/${name}.err"
  problems_file="${work_dir}/${name}.problems"
  : >"${problems_file}"

  # Keep going after a failure so one bad formula does not hide the rest.
  set +e
  env -u GITHUB_ACTIONS brew audit --strict --display-filename "${fq}" \
    >"${stdout_file}" 2>"${stderr_file}"
  status=$?
  set -e

  tolerated=0
  while IFS= read -r line
  do
    [[ -n "${line}" ]] || continue
    if [[ "${line}" == *"${tolerated_suffix}" ]]
    then
      tolerated=$((tolerated + 1))
    else
      printf '%s\n' "${line}" >>"${problems_file}"
    fi
  done <"${stdout_file}"

  # Anything that is not the tolerated problem is a real problem.
  if [[ -s "${problems_file}" ]]
  then
    while IFS= read -r line
    do
      echo "::error file=$(annotation_path "${tap_dir}/Formula/${name}.rb")::${line}"
    done <"${problems_file}"
    rc=1
  fi

  # The tolerated problem is expected exactly once for a formula that tracks
  # a branch -- but only in a Homebrew that has the rule. A Homebrew without
  # the rule never reports it, so nothing is expected there.
  expected=0
  if [[ "${rule_state}" == "present" ]] && [[ "${mode}" == "branch" ]]
  then
    expected=1
  fi

  # A broken probe has already been reported above; checking the expectation
  # on top of that would only add noise.
  if [[ "${rule_state}" != "broken" ]] && [[ "${tolerated}" -ne "${expected}" ]]
  then
    if [[ "${tolerated}" -gt 0 ]] && [[ "${mode}" == "pinned" ]]
    then
      echo "::error::${fq}: reports the 'full commit hash in revision' problem" \
        "(${tolerated} times) but does not track a branch; pin the source with" \
        "a 'revision:' or fix the formula"
    elif [[ "${tolerated}" -gt 1 ]]
    then
      echo "::error::${fq}: reports the 'full commit hash in revision' problem" \
        "(${tolerated} times) but tracks a single branch; fix the extra sources"
    elif [[ "${rule_state}" != "present" ]]
    then
      # The rule is not in this Homebrew, so it cannot have reported the
      # problem. The audit reported it anyway, which means some other rule
      # prints the same text -- a genuine problem, not the tolerated one.
      echo "::error::${fq}: reports the 'full commit hash in revision' problem," \
        "but this Homebrew does not have that rule; the message must come from" \
        "somewhere else -- update script/audit.sh"
    else
      echo "::error::${fq}: expected the 'full commit hash in revision' problem" \
        "for a formula that tracks a branch, but the audit did not report it;" \
        "upstream may have changed the rule -- update script/audit.sh"
    fi
    rc=1
  fi

  # `brew audit` failed without printing a problem: it could not audit the
  # formula at all (unknown name, an internal error, ...).
  if [[ "${status}" -ne 0 ]] && [[ ! -s "${problems_file}" ]] && [[ "${tolerated}" -eq 0 ]]
  then
    echo "::error::${fq}: brew audit failed without reporting a problem:"
    while IFS= read -r line
    do
      echo "::error::${line}"
    done <"${stderr_file}"
    rc=1
  fi
done

if [[ "${audited}" -eq 0 ]]
then
  echo "::error::no formulae found in ${tap_dir}/Formula"
  rc=1
fi

exit "${rc}"
