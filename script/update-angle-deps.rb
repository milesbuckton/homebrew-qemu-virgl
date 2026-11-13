#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require_relative "../lib/deps_guard"
require "base64"
require "net/http"
require "uri"

formula_path = File.expand_path("../Formula/libangle.rb", __dir__)
formula_content = File.read(formula_path, encoding: "UTF-8")

deps_uri = URI("https://chromium.googlesource.com/angle/angle/+/refs/heads/main/DEPS?format=TEXT")
response = Net::HTTP.get_response(deps_uri)
raise "Failed to fetch DEPS: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

deps_text = Base64.decode64(response.body)

revisions = DepsGuard.deps_revisions(deps_text)
vars = DepsGuard.parse_vars(deps_text)

# The resource -> DEPS maps live in Formula/libangle.rb (DEPS_ENTRIES and
# DEPS_VAR_ENTRIES). The formula cannot be loaded outside Homebrew, so the two
# hash literals are read from its source rather than duplicated here.
formula_hash = lambda do |constant|
  body = formula_content[/^\s*#{constant} = \{(.*?)^\s*\}\.freeze/m, 1]
  raise "Could not locate #{constant} in Formula/libangle.rb" if body.nil?

  entries = body.scan(/"([^"]+)"\s*=>\s*"([^"]+)"/).to_h
  raise "#{constant} in Formula/libangle.rb is empty" if entries.empty?

  entries
end

deps_entries = formula_hash.call("DEPS_ENTRIES")
deps_var_entries = formula_hash.call("DEPS_VAR_ENTRIES")

updated = formula_content.dup
changes = []

deps_entries.each do |res_name, deps_key|
  new_rev = revisions[deps_key]
  raise "ANGLE's DEPS no longer pins #{deps_key} (resource #{res_name})" unless new_rev

  pattern = /(resource "#{Regexp.escape(res_name)}" do\s*\n\s*url [^\n]+\n\s*revision:\s*")([0-9a-f]{40})(")/
  unless updated =~ pattern
    raise "Could not locate resource block for #{res_name} (#{deps_key}) in Formula/libangle.rb"
  end

  old_rev = Regexp.last_match(2)
  next if old_rev == new_rev

  updated.sub!(pattern, "\\1#{new_rev}\\3")
  changes << "#{res_name} (#{deps_key}): #{old_rev[0..7]} -> #{new_rev[0..7]}"
end

deps_var_entries.each do |res_name, var_name|
  new_rev = vars[var_name]
  raise "ANGLE's DEPS no longer defines var #{var_name} (resource #{res_name})" unless new_rev

  pattern = /(resource "#{Regexp.escape(res_name)}" do\s*\n\s*url [^\n]+\n\s*revision:\s*")([0-9a-f]{40})(")/
  unless updated =~ pattern
    raise "Could not locate resource block for #{res_name} (var #{var_name}) in Formula/libangle.rb"
  end

  old_rev = Regexp.last_match(2)
  next if old_rev == new_rev

  updated.sub!(pattern, "\\1#{new_rev}\\3")
  changes << "#{res_name} (var #{var_name}): #{old_rev[0..7]} -> #{new_rev[0..7]}"
end

if changes.empty?
  puts "Formula/libangle.rb staged resources are already up to date with DEPS."
else
  File.write(formula_path, updated)
  puts "Updated Formula/libangle.rb with #{changes.size} revision bump(s):"
  changes.each { |change| puts "  - #{change}" }
end
