#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require_relative "../lib/deps_guard"
require "base64"
require "net/http"
require "uri"

formula_path = File.expand_path("../Formula/libangle.rb", __dir__)
formula_content = File.read(formula_path)

deps_uri = URI("https://chromium.googlesource.com/angle/angle/+/refs/heads/main/DEPS?format=TEXT")
response = Net::HTTP.get_response(deps_uri)
raise "Failed to fetch DEPS: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

deps_text = Base64.decode64(response.body)

revisions = DepsGuard.deps_revisions(deps_text)
vars = DepsGuard.parse_vars(deps_text)

deps_entries = {
  "chromium-build"   => "build",
  "chromium-testing" => "testing",
  "chromium-zlib"    => "third_party/zlib",
  "chromium-zstd"    => "third_party/zstd/src",
  "vulkan-headers"   => "third_party/vulkan-headers/src",
  "spirv-headers"    => "third_party/spirv-headers/src",
  "spirv-tools"      => "third_party/spirv-tools/src",
  "astc-encoder"     => "third_party/astc-encoder/src",
  "chromium-jsoncpp" => "third_party/jsoncpp",
}

deps_var_entries = {
  "jsoncpp-source" => "jsoncpp_revision",
}

updated = formula_content.dup
changes = []

deps_entries.each do |res_name, deps_key|
  new_rev = revisions[deps_key]
  next unless new_rev

  pattern = /(resource "#{Regexp.escape(res_name)}" do\s*\n\s*url [^\n]+\n\s*revision:\s*")([0-9a-f]{40})(")/
  next unless updated =~ pattern

  old_rev = Regexp.last_match(2)
  next if old_rev == new_rev

  updated.sub!(pattern, "\\1#{new_rev}\\3")
  changes << "#{res_name} (#{deps_key}): #{old_rev[0..7]} -> #{new_rev[0..7]}"
end

deps_var_entries.each do |res_name, var_name|
  new_rev = vars[var_name]
  next unless new_rev

  pattern = /(resource "#{Regexp.escape(res_name)}" do\s*\n\s*url [^\n]+\n\s*revision:\s*")([0-9a-f]{40})(")/
  next unless updated =~ pattern

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
