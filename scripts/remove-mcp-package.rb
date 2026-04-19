#!/usr/bin/env ruby
# Removes the swift-sdk Swift Package dependency that was added earlier.
# We've decided to hand-roll the MCP JSON-RPC protocol directly over stdio
# because Xcode's SPM integration was failing to resolve swift-nio's
# transitive module graph under the current toolchain.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../../time.md.xcodeproj', __FILE__)
project = Xcodeproj::Project.open(PROJECT_PATH)

cli_target = project.targets.find { |t| t.name == 'timemd-mcp' }
raise 'timemd-mcp target not found' unless cli_target

# 1. Remove the MCP product from the cli target's frameworks build phase
frameworks_phase = cli_target.build_phases.find { |p| p.isa == 'PBXFrameworksBuildPhase' }
if frameworks_phase
  mcp_files = frameworks_phase.files.select do |bf|
    bf.product_ref && bf.product_ref.respond_to?(:product_name) && bf.product_ref.product_name == 'MCP'
  end
  mcp_files.each do |bf|
    puts "  - Removing MCP from Frameworks build phase"
    frameworks_phase.files.delete(bf)
    bf.remove_from_project
  end
end

# 2. Remove from packageProductDependencies
if cli_target.package_product_dependencies
  to_remove = cli_target.package_product_dependencies.select do |dep|
    dep.product_name == 'MCP'
  end
  to_remove.each do |dep|
    puts "  - Removing MCP from cli target packageProductDependencies"
    cli_target.package_product_dependencies.delete(dep)
    dep.remove_from_project
  end
end

# 3. Remove the XCRemoteSwiftPackageReference entry
refs_to_remove = project.root_object.package_references.select do |ref|
  ref.repositoryURL.to_s.include?('modelcontextprotocol/swift-sdk')
end
refs_to_remove.each do |ref|
  puts "  - Removing XCRemoteSwiftPackageReference for swift-sdk"
  project.root_object.package_references.delete(ref)
  ref.remove_from_project
end

puts 'Saving...'
project.save
puts 'Done.'
