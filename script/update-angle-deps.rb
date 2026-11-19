#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require_relative "../lib/deps_guard"
require "base64"
require "net/http"
require "uri"

formula_path = File.expand_path("../Formula/libangle.rb", __dir__)
formula_content = File.read(formula_path, encoding: "UTF-8")

fetch_with_retry = lambda do |url, max_attempts: 5|
  uri = URI(url)
  attempts = 0

  loop do
    attempts += 1
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 15
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "homebrew-qemu-virgl"

      response = http.request(request)
      break response if response.is_a?(Net::HTTPSuccess)

      is_transient = response.is_a?(Net::HTTPServerError) || response.is_a?(Net::HTTPTooManyRequests)
      if !is_transient || attempts >= max_attempts
        raise "Failed to fetch #{uri}: HTTP #{response.code} #{response.message}"
      end

      warn "Failed to fetch #{uri} (HTTP #{response.code} #{response.message}); " \
           "retrying in #{2**attempts}s (attempt #{attempts}/#{max_attempts})..."
    rescue Net::OpenTimeout, Net::ReadTimeout, IOError, SystemCallError, SocketError => e
      raise "Failed to fetch #{uri} after #{attempts} attempts: #{e.message}" if attempts >= max_attempts

      warn "Failed to fetch #{uri} (#{e.class}: #{e.message}); " \
           "retrying in #{2**attempts}s (attempt #{attempts}/#{max_attempts})..."
    end

    sleep(2**attempts)
  end
end

primary_deps_url = "https://chromium.googlesource.com/angle/angle/+/refs/heads/main/DEPS?format=TEXT"
fallback_deps_url = "https://raw.githubusercontent.com/google/angle/main/DEPS"

deps_text = begin
  response = fetch_with_retry.call(primary_deps_url)
  Base64.decode64(response.body)
rescue => e
  warn "Primary DEPS fetch failed: #{e.message}. Trying GitHub mirror fallback..."
  fetch_with_retry.call(fallback_deps_url).body
end

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
