#!/usr/bin/env ruby
# frozen_string_literal: true

application, digest, values_path = ARGV
values_path ||= File.expand_path("../environments/production.yaml", __dir__)

abort "usage: update-image-digest.rb APPLICATION SHA256_DIGEST [VALUES_FILE]" unless application && digest
abort "invalid application name: #{application}" unless application.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/)
abort "digest must be an immutable sha256 digest" unless digest.match?(/\Asha256:[a-f0-9]{64}\z/)

lines = File.readlines(values_path)
application_header = /^  #{Regexp.escape(application)}:\s*$/
next_application = /^  [a-z0-9][a-z0-9-]*:\s*$/

in_application = false
in_image = false
matches = 0
changed = false

lines.map! do |line|
  if line.match?(application_header)
    in_application = true
    in_image = false
  elsif in_application && line.match?(next_application)
    in_application = false
    in_image = false
  elsif in_application && line.match?(/^    image:\s*$/)
    in_image = true
  elsif in_application && in_image && line.match?(/^    [a-zA-Z]/)
    in_image = false
  end

  next line unless in_application && in_image && line.match?(/^      digest:\s*/)

  matches += 1
  replacement = "      digest: #{digest}\n"
  changed ||= line != replacement
  replacement
end

abort "application #{application.inspect} does not have exactly one image digest in #{values_path}" unless matches == 1

File.write(values_path, lines.join) if changed
puts(changed ? "updated #{application} to #{digest}" : "#{application} already uses #{digest}")

if ENV["GITHUB_OUTPUT"] && !ENV["GITHUB_OUTPUT"].empty?
  File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |output| output.puts "changed=#{changed}" }
end
