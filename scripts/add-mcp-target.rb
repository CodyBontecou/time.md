#!/usr/bin/env ruby
# Adds the `timemd-mcp` executable target to time.md.xcodeproj and wires it up:
#   - Swift Package dependency on modelcontextprotocol/swift-sdk
#   - Explicit file references for timemd-mcp/*.swift
#   - Command-line tool product with macOS 14.0 deployment target
#   - Copy Files build phase on the main time.md target that embeds the built
#     binary into the app bundle's Resources directory
#   - Target dependency so the CLI builds before the main app
#   - iOS target exclusion for App/MCPIntegrationService.swift
#
# Idempotent: re-running will skip steps that have already been applied.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../../time.md.xcodeproj', __FILE__)
CLI_DIR      = 'timemd-mcp'
CLI_NAME     = 'timemd-mcp'
MCP_REPO     = 'https://github.com/modelcontextprotocol/swift-sdk.git'
MCP_MIN_VER  = '0.11.0'
SOURCE_FILES = %w[main.swift Database.swift Range.swift Tools.swift Handlers.swift]
IOS_EXCLUDE  = 'App/MCPIntegrationService.swift'

puts "Opening #{PROJECT_PATH}"
project = Xcodeproj::Project.open(PROJECT_PATH)

main_target = project.targets.find { |t| t.name == 'time.md' }
ios_target  = project.targets.find { |t| t.name == 'time.mdIOS' }
raise 'Main time.md target not found' unless main_target

# ---------------------------------------------------------------------------
# 1. Swift Package reference + MCP product dependency
# ---------------------------------------------------------------------------
mcp_package_ref = project.root_object.package_references.find do |ref|
  ref.repositoryURL.to_s.include?('modelcontextprotocol/swift-sdk')
end

if mcp_package_ref.nil?
  puts '  + Adding XCRemoteSwiftPackageReference for swift-sdk'
  mcp_package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  mcp_package_ref.repositoryURL = MCP_REPO
  mcp_package_ref.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => MCP_MIN_VER
  }
  project.root_object.package_references << mcp_package_ref
else
  puts '  ✓ XCRemoteSwiftPackageReference for swift-sdk already present'
end

mcp_product_dep = project.objects.select do |o|
  o.isa == 'XCSwiftPackageProductDependency' && o.product_name == 'MCP'
end.first

if mcp_product_dep.nil?
  puts '  + Creating XCSwiftPackageProductDependency for MCP'
  mcp_product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  mcp_product_dep.package = mcp_package_ref
  mcp_product_dep.product_name = 'MCP'
else
  puts '  ✓ XCSwiftPackageProductDependency for MCP already present'
end

# ---------------------------------------------------------------------------
# 2. Create / fetch the timemd-mcp native target
# ---------------------------------------------------------------------------
cli_target = project.targets.find { |t| t.name == CLI_NAME }

if cli_target.nil?
  puts "  + Creating PBXNativeTarget '#{CLI_NAME}' (command-line tool)"
  cli_target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
  cli_target.name = CLI_NAME
  cli_target.product_name = CLI_NAME
  cli_target.product_type = 'com.apple.product-type.tool'

  # Product reference in the Products group
  products_group = project.products_group
  product_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  product_ref.path = CLI_NAME
  product_ref.source_tree = 'BUILT_PRODUCTS_DIR'
  product_ref.explicit_file_type = 'compiled.mach-o.executable'
  product_ref.include_in_index = '0'
  products_group << product_ref
  cli_target.product_reference = product_ref

  # Build configuration list
  debug_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  debug_config.name = 'Debug'
  release_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  release_config.name = 'Release'
  common = {
    'PRODUCT_NAME' => CLI_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bontecou.time.md.mcp',
    'SDKROOT' => 'macosx',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'SWIFT_VERSION' => '5.0',
    'SKIP_INSTALL' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => '67KC823C9A',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    'ALWAYS_SEARCH_USER_PATHS' => 'NO',
    'SWIFT_DEFAULT_ACTOR_ISOLATION' => 'nonisolated',
    'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
    'SUPPORTED_PLATFORMS' => 'macosx'
  }
  debug_config.build_settings = common.merge(
    'SWIFT_OPTIMIZATION_LEVEL' => '-Onone',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG',
    'ONLY_ACTIVE_ARCH' => 'YES'
  )
  release_config.build_settings = common.merge(
    'SWIFT_OPTIMIZATION_LEVEL' => '-O',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  )

  config_list = project.new(Xcodeproj::Project::Object::XCConfigurationList)
  config_list.default_configuration_name = 'Release'
  config_list.default_configuration_is_visible = '0'
  config_list.build_configurations << debug_config
  config_list.build_configurations << release_config
  cli_target.build_configuration_list = config_list

  project.targets << cli_target
else
  puts "  ✓ PBXNativeTarget '#{CLI_NAME}' already present"
end

# ---------------------------------------------------------------------------
# 3. Source group + file references
# ---------------------------------------------------------------------------
cli_group = project.main_group.children.find do |child|
  child.respond_to?(:name) && (child.name == CLI_DIR || child.path == CLI_DIR)
end

if cli_group.nil?
  puts "  + Creating PBXGroup for #{CLI_DIR}"
  cli_group = project.main_group.new_group(CLI_DIR, CLI_DIR)
else
  puts "  ✓ PBXGroup for #{CLI_DIR} already present"
end

sources_phase = cli_target.build_phases.find { |p| p.isa == 'PBXSourcesBuildPhase' }
if sources_phase.nil?
  puts '  + Creating Sources build phase for timemd-mcp'
  sources_phase = project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
  cli_target.build_phases << sources_phase
end

SOURCE_FILES.each do |file|
  existing = cli_group.children.find { |c| c.respond_to?(:path) && c.path == file }
  if existing.nil?
    puts "  + Adding source file #{file}"
    ref = cli_group.new_reference(file)
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.file_ref = ref
    sources_phase.files << build_file
  else
    already_in_phase = sources_phase.files.any? { |bf| bf.file_ref == existing }
    unless already_in_phase
      puts "  + Re-adding #{file} to Sources phase"
      build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      build_file.file_ref = existing
      sources_phase.files << build_file
    else
      puts "  ✓ Source file #{file} already wired"
    end
  end
end

# ---------------------------------------------------------------------------
# 4. Frameworks phase + MCP product dependency on cli target
# ---------------------------------------------------------------------------
frameworks_phase = cli_target.build_phases.find { |p| p.isa == 'PBXFrameworksBuildPhase' }
if frameworks_phase.nil?
  puts '  + Creating Frameworks build phase for timemd-mcp'
  frameworks_phase = project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
  cli_target.build_phases << frameworks_phase
end

already_linked = frameworks_phase.files.any? do |bf|
  bf.product_ref == mcp_product_dep
end
if !already_linked
  puts '  + Linking MCP product into timemd-mcp Frameworks phase'
  link_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  link_build_file.product_ref = mcp_product_dep
  frameworks_phase.files << link_build_file
else
  puts '  ✓ MCP product already linked'
end

cli_target.package_product_dependencies ||= []
unless cli_target.package_product_dependencies.include?(mcp_product_dep)
  puts '  + Adding MCP to cli target packageProductDependencies'
  cli_target.package_product_dependencies << mcp_product_dep
else
  puts '  ✓ MCP already in cli target packageProductDependencies'
end

# ---------------------------------------------------------------------------
# 5. Copy Files build phase on main target → embed binary in Resources
# ---------------------------------------------------------------------------
copy_phase = main_target.build_phases.find do |p|
  p.isa == 'PBXCopyFilesBuildPhase' && p.name == 'Embed timemd-mcp'
end

if copy_phase.nil?
  puts '  + Adding Copy Files phase "Embed timemd-mcp" to main target'
  copy_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  copy_phase.name = 'Embed timemd-mcp'
  copy_phase.dst_subfolder_spec = '7'  # Resources
  copy_phase.dst_path = ''
  copy_phase.run_only_for_deployment_postprocessing = '0'

  copy_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  copy_build_file.file_ref = cli_target.product_reference
  copy_build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  copy_phase.files << copy_build_file

  main_target.build_phases << copy_phase
else
  puts '  ✓ Copy Files phase "Embed timemd-mcp" already present'
end

# ---------------------------------------------------------------------------
# 6. Target dependency so cli builds before main app
# ---------------------------------------------------------------------------
has_dep = main_target.dependencies.any? { |d| d.target == cli_target }
if !has_dep
  puts '  + Adding cli target as dependency of main target'
  main_target.add_dependency(cli_target)
else
  puts '  ✓ CLI already a dependency of main target'
end

# ---------------------------------------------------------------------------
# 7. Save — iOS exclusion for MCPIntegrationService.swift handled as a
# post-save text patch (PBXFileSystemSynchronizedBuildFileExceptionSet is
# not modelled by older Xcodeproj gem versions).
# ---------------------------------------------------------------------------
puts 'Saving project...'
project.save
puts 'Saved.'

# Post-save: patch iOS exception list if needed.
pbxproj = File.join(PROJECT_PATH, 'project.pbxproj')
text = File.read(pbxproj)
unless text.include?("App/MCPIntegrationService.swift,")
  puts "  + Patching iOS exception list to exclude #{IOS_EXCLUDE}"
  patched = text.sub(
    /(App\/BrowserSettingsStore\.swift,\n\s*App\/time\.mdCommands\.swift,)/,
    "App/BrowserSettingsStore.swift,\n\t\t\t\tApp/MCPIntegrationService.swift,\n\t\t\t\tApp/time.mdCommands.swift,"
  )
  if patched == text
    warn "  ! Could not find iOS exception anchor — manual add may be required"
  else
    File.write(pbxproj, patched)
    puts '  ✓ iOS exception list patched'
  end
else
  puts '  ✓ iOS exception list already excludes MCPIntegrationService.swift'
end

puts 'Done.'
