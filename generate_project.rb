#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates PinNote.xcodeproj using the xcodeproj gem.
# Run: ruby generate_project.rb

$LOAD_PATH.unshift(File.expand_path('~/.gem/ruby/2.6.0/gems', __dir__))
Dir["#{File.expand_path('~/.gem/ruby/2.6.0/gems', __dir__)}/*/lib"].each { |p| $LOAD_PATH.unshift(p) }

require 'xcodeproj'
require 'fileutils'

ROOT        = File.expand_path('..', __FILE__).sub(/\/generate_project\.rb$/, '')
             .then { |d| File.expand_path(d) }
# Actually let's be explicit
ROOT        = File.dirname(File.expand_path(__FILE__))
PROJ_PATH   = "#{ROOT}/PinNote.xcodeproj"
APP_NAME    = 'PinNote'
WIDGET_NAME = 'PinNoteLiveActivity'
BUNDLE_BASE = 'com.yourdomain.PinNote'   # ← change to your Team bundle ID
IOS_VER     = '17.0'

puts "Project root: #{ROOT}"

# ────────────── Remove stale .xcodeproj if present ──────────────────
FileUtils.rm_rf(PROJ_PATH) if File.exist?(PROJ_PATH)

# ────────────────────────── New project ─────────────────────────────
proj = Xcodeproj::Project.new(PROJ_PATH)

# ──────────────────────────── Groups ────────────────────────────────
main_g   = proj.main_group
app_g    = main_g.new_group(APP_NAME,    APP_NAME)
widget_g = main_g.new_group(WIDGET_NAME, WIDGET_NAME)

# App subgroups
sub = %w[App Models Shared Design Controllers Views Managers Intents].each_with_object({}) do |name, h|
  h[name] = app_g.new_group(name, name)
end

# ───────────────────────── File references ──────────────────────────
app_sources    = []
widget_sources = []

# App Swift files
{
  'App'         => %w[AppDelegate.swift SceneDelegate.swift],
  'Models'      => %w[Note.swift NoteStore.swift],
  'Design'      => %w[DesignSystem.swift ThemeManager.swift],
  'Controllers' => %w[SplashViewController.swift OnboardingViewController.swift
                      NoteListViewController.swift NoteDetailViewController.swift
                      SettingsViewController.swift],
  'Views'       => %w[NoteCell.swift BottomBars.swift],
  'Managers'    => %w[LiveActivityManager.swift PurchaseManager.swift],
}.each do |dir, files|
  files.each do |f|
    ref = sub[dir].new_file(f)
    ref.last_known_file_type = 'sourcecode.swift'
    app_sources << ref
  end
end

# Shared files — compiled into both targets
['PinNoteActivityAttributes.swift', 'CreateNoteIntent.swift'].each do |f|
  ref = sub['Shared'].new_file(f)
  ref.last_known_file_type = 'sourcecode.swift'
  app_sources    << ref
  widget_sources << ref
end

# App resources
app_info_ref   = app_g.new_file('Info.plist')
app_info_ref.last_known_file_type = 'text.plist.xml'

app_assets_ref = app_g.new_file('Assets.xcassets')
app_assets_ref.last_known_file_type = 'folder.assetcatalog'

# Widget Swift files
['PinNoteLiveActivityView.swift'].each do |f|
  ref = widget_g.new_file(f)
  ref.last_known_file_type = 'sourcecode.swift'
  widget_sources << ref
end

widget_info_ref   = widget_g.new_file('Info.plist')
widget_info_ref.last_known_file_type = 'text.plist.xml'

widget_assets_ref = widget_g.new_file('Assets.xcassets')
widget_assets_ref.last_known_file_type = 'folder.assetcatalog'

# ─────────────────────────── Targets ────────────────────────────────

# Main app
app_target = proj.new_target(:application, APP_NAME, :ios, IOS_VER)
app_target.add_file_references(app_sources)
app_target.resources_build_phase.add_file_reference(app_assets_ref)

# Widget extension
widget_target = proj.new_target(:app_extension, WIDGET_NAME, :ios, IOS_VER)
widget_target.add_file_references(widget_sources)
widget_target.resources_build_phase.add_file_reference(widget_assets_ref)

# Embed extension into the app (PlugIns folder, subfolder spec 13)
embed_phase = app_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.dst_subfolder_spec = '13'
embed_file = embed_phase.add_file_reference(widget_target.product_reference)
embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# ─────────────── Build settings: project level ──────────────────────
proj.build_configurations.each do |config|
  s = config.build_settings
  s['ALWAYS_SEARCH_USER_PATHS']   = 'NO'
  s['CLANG_ENABLE_MODULES']       = 'YES'
  s['SWIFT_VERSION']              = '5.0'
end

# ─────────────── Build settings: app target ─────────────────────────
app_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']          = BUNDLE_BASE
  s['MARKETING_VERSION']                  = '1.0'
  s['CURRENT_PROJECT_VERSION']            = '1'
  s['SWIFT_VERSION']                      = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']         = IOS_VER
  s['TARGETED_DEVICE_FAMILY']             = '1'
  s['INFOPLIST_FILE']                     = "#{APP_NAME}/Info.plist"
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['CODE_SIGN_STYLE']                    = 'Automatic'
  s['DEVELOPMENT_TEAM']                   = ''
  s['SWIFT_EMIT_LOC_STRINGS']             = 'YES'
  s['GENERATE_INFOPLIST_FILE']            = 'NO'
  s.delete('INFOPLIST_KEY_UIMainStoryboardFile')   rescue nil
  if config.name == 'Debug'
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    s['DEBUG_INFORMATION_FORMAT'] = 'dwarf'
    s['ENABLE_TESTABILITY']       = 'YES'
    s['MTL_ENABLE_DEBUG_INFO']    = 'INCLUDE_SOURCE'
  else
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-Owholemodule'
    s['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    s['ENABLE_TESTABILITY']       = 'NO'
  end
end

# ─────────────── Build settings: widget target ──────────────────────
widget_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']          = "#{BUNDLE_BASE}.LiveActivity"
  s['MARKETING_VERSION']                  = '1.0'
  s['CURRENT_PROJECT_VERSION']            = '1'
  s['SWIFT_VERSION']                      = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']         = IOS_VER
  s['TARGETED_DEVICE_FAMILY']             = '1'
  s['INFOPLIST_FILE']                     = "#{WIDGET_NAME}/Info.plist"
  s.delete('ASSETCATALOG_COMPILER_APPICON_NAME')
  s['CODE_SIGN_STYLE']                    = 'Automatic'
  s['DEVELOPMENT_TEAM']                   = ''
  s['SKIP_INSTALL']                       = 'YES'
  s['SWIFT_EMIT_LOC_STRINGS']             = 'YES'
  s['GENERATE_INFOPLIST_FILE']            = 'NO'
end

# ──────────────────────────── Save ──────────────────────────────────
proj.save
puts "✅  Created: #{PROJ_PATH}"
puts
puts "Next steps:"
puts "  1. Open PinNote.xcodeproj in Xcode"
puts "  2. Set your Team in Signing & Capabilities for both targets"
puts "  3. Change bundle IDs from 'com.yourdomain.PinNote' to something unique"
puts "  4. For Live Activities: add Push Notifications + iCloud capabilities"
