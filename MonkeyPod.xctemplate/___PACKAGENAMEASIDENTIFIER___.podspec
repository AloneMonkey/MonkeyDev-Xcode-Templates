Pod::Spec.new do |spec|
  spec.name = "___PACKAGENAMEASIDENTIFIER___"
  spec.version = "1.0.0"
  spec.summary = "CaptainHook plugin for MonkeyDev"
  # Replace publishing metadata with your own before distributing this Pod.
  spec.homepage = "https://example.com/#{spec.name}"
  spec.license = { :type => "BSD" }
  spec.author = "___FULLUSERNAME___"
  spec.source = { :git => "https://example.com/#{spec.name}.git", :tag => spec.version.to_s }

  spec.ios.deployment_target = "15.0"
  # The podspec is generated alongside the plugin sources.
  spec.source_files = "*.{h,m,mm}", "Sources/**/*.{h,m,mm}"
  spec.public_header_files = "___PACKAGENAMEASIDENTIFIER___.h"
  spec.frameworks = "Foundation", "UIKit"
  spec.requires_arc = true
  spec.pod_target_xcconfig = {
    "MonkeyDevPath" => "/opt/MonkeyDev",
    "HEADER_SEARCH_PATHS" => '$(inherited) "$(MonkeyDevPath)/include"'
  }
end
