#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

REPOSITORY_ROOT = File.expand_path('..', __dir__)
WIDGET_TARGET_NAME = 'BnbuWidgets'
WIDGET_SOURCE_GROUP = '../apple/BnbuWidgets'

def file_reference(group, name)
  group.files.find { |file| file.path == name } || group.new_file(name)
end

def add_framework(project, target, name)
  framework_path = "System/Library/Frameworks/#{name}.framework"
  reference = project.frameworks_group.files.find do |file|
    file.path == framework_path
  end
  reference ||= project.frameworks_group.new_file(framework_path)
  return if target.frameworks_build_phase.files_references.include?(reference)

  target.frameworks_build_phase.add_file_reference(reference, true)
end

def configure_widget_project(
  relative_project_path:,
  platform:,
  deployment_target:,
  bundle_identifiers:,
  configuration_files:,
  configure_main:
)
  project_path = File.join(REPOSITORY_ROOT, relative_project_path)
  project = Xcodeproj::Project.open(project_path)
  runner = project.targets.find { |target| target.name == 'Runner' }
  raise "Runner target missing from #{relative_project_path}" unless runner

  widget = project.targets.find { |target| target.name == WIDGET_TARGET_NAME }
  widget ||= project.new_target(
    :app_extension,
    WIDGET_TARGET_NAME,
    platform,
    deployment_target
  )

  group = project.main_group.groups.find do |candidate|
    candidate.name == WIDGET_TARGET_NAME
  end
  group ||= project.main_group.new_group(WIDGET_TARGET_NAME, WIDGET_SOURCE_GROUP)
  source = file_reference(group, 'BnbuWidget.swift')
  file_reference(group, 'Info.plist')
  file_reference(group, 'BnbuWidgets.entitlements')
  unless widget.source_build_phase.files_references.include?(source)
    widget.add_file_references([source])
  end

  add_framework(project, widget, 'WidgetKit')
  add_framework(project, widget, 'SwiftUI')

  runner.add_dependency(widget) unless runner.dependencies.any? do |dependency|
    dependency.target == widget
  end
  embed_phase = runner.copy_files_build_phases.find do |phase|
    phase.name == 'Embed Foundation Extensions'
  end
  embed_phase ||= runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.dst_subfolder_spec = '13'
  unless embed_phase.files_references.include?(widget.product_reference)
    embed_phase.add_file_reference(widget.product_reference, true)
  end
  flutter_thin_phase = runner.build_phases.find do |phase|
    ['Thin Binary', 'ShellScript'].include?(phase.display_name)
  end
  if flutter_thin_phase
    runner.build_phases.delete(embed_phase)
    runner.build_phases.insert(
      runner.build_phases.index(flutter_thin_phase),
      embed_phase
    )
  end

  widget.build_configurations.each do |configuration|
    configuration_file = configuration_files.fetch(configuration.name)
    expected_configuration_path = File.join(
      File.dirname(project_path),
      'Flutter',
      configuration_file
    )
    configuration_reference = project.files.find do |reference|
      reference.real_path.to_s == expected_configuration_path
    end
    configuration_reference ||= project.main_group.new_file(
      "Flutter/#{configuration_file}"
    )
    configuration.base_configuration_reference = configuration_reference
    settings = configuration.build_settings
    settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    settings['CODE_SIGN_ENTITLEMENTS'] = '$(SRCROOT)/../apple/BnbuWidgets/BnbuWidgets.entitlements'
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['INFOPLIST_FILE'] = '$(SRCROOT)/../apple/BnbuWidgets/Info.plist'
    settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_identifiers.fetch(
      configuration.name
    )
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['SKIP_INSTALL'] = 'YES'
    settings['SWIFT_VERSION'] = '5.0'
    yield(settings, configuration.name) if block_given?
  end

  configure_main.call(runner)
  project.save
end

configure_widget_project(
  relative_project_path: 'ios/Runner.xcodeproj',
  platform: :ios,
  deployment_target: '17.0',
  bundle_identifiers: {
    'Debug' => '$(BNBU_IOS_DEVELOPMENT_WIDGET_BUNDLE_IDENTIFIER)',
    'Profile' => '$(BNBU_IOS_DEVELOPMENT_WIDGET_BUNDLE_IDENTIFIER)',
    'Release' => '$(BNBU_IOS_RELEASE_WIDGET_BUNDLE_IDENTIFIER)'
  },
  configuration_files: {
    'Debug' => 'WidgetDebug.xcconfig',
    'Profile' => 'WidgetDebug.xcconfig',
    'Release' => 'WidgetRelease.xcconfig'
  },
  configure_main: lambda do |runner|
    runner.build_configurations.each do |configuration|
      release = configuration.name == 'Release'
      settings = configuration.build_settings
      settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
      settings['BNBU_IOS_APP_GROUP_IDENTIFIER'] = if release
                                                    '$(BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER)'
                                                  else
                                                    '$(BNBU_IOS_DEVELOPMENT_APP_GROUP_IDENTIFIER)'
                                                  end
      settings['DEVELOPMENT_TEAM'] = if release
                                       '$(BNBU_IOS_RELEASE_TEAM)'
                                     else
                                       '$(BNBU_IOS_DEVELOPMENT_TEAM)'
                                     end
      settings['PRODUCT_BUNDLE_IDENTIFIER'] = if release
                                                '$(BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER)'
                                              else
                                                '$(BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER)'
                                              end
    end
  end
) do |settings, configuration_name|
  release = configuration_name == 'Release'
  settings['BNBU_WIDGET_DISPLAY_NAME'] = 'BNBU.ME · iPhone'
  settings['BNBU_IOS_APP_GROUP_IDENTIFIER'] = if release
                                                '$(BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER)'
                                              else
                                                '$(BNBU_IOS_DEVELOPMENT_APP_GROUP_IDENTIFIER)'
                                              end
  settings['DEVELOPMENT_TEAM'] = if release
                                   '$(BNBU_IOS_RELEASE_TEAM)'
                                 else
                                   '$(BNBU_IOS_DEVELOPMENT_TEAM)'
                                 end
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
end

configure_widget_project(
  relative_project_path: 'macos/Runner.xcodeproj',
  platform: :osx,
  deployment_target: '14.0',
  bundle_identifiers: {
    'Debug' => '$(BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER)',
    'Profile' => '$(BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER)',
    'Release' => '$(BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER)'
  },
  configuration_files: {
    'Debug' => 'Widget.xcconfig',
    'Profile' => 'Widget.xcconfig',
    'Release' => 'Widget.xcconfig'
  },
  configure_main: lambda do |runner|
    runner.build_configurations.each do |configuration|
      configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] =
        '$(BNBU_MACOS_APP_BUNDLE_IDENTIFIER)'
    end
  end
) do |settings, configuration_name|
  settings['BNBU_WIDGET_DISPLAY_NAME'] = 'BNBU.ME · Mac'
  settings['CODE_SIGN_ENTITLEMENTS'] = if configuration_name == 'Release'
                                        'Runner/WidgetBuild.entitlements'
                                      else
                                        'Runner/Widget.entitlements'
                                      end
  settings['FRAMEWORK_SEARCH_PATHS'] = ''
  settings['HEADER_SEARCH_PATHS'] = ''
  settings['LIBRARY_SEARCH_PATHS'] = ''
  settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/../Frameworks',
    '@executable_path/../../../../Frameworks'
  ]
  settings['OTHER_LDFLAGS'] = ''
end
