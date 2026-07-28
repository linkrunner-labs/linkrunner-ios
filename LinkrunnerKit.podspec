Pod::Spec.new do |s|
  s.name             = 'LinkrunnerKit'
  s.version          = '4.1.0'
  s.summary          = 'AI‑powered Mobile Measurement SDK.'
  s.description      = <<-DESC
    Native Swift SDK for Linkrunner.io—attribution, event & payment tracking.
  DESC
  s.homepage         = 'https://github.com/linkrunner-labs/linkrunner-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Linkrunner' => 'darshil@linkrunner.io' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.source           = { :git => 'https://github.com/linkrunner-labs/linkrunner-ios.git', :tag => s.version.to_s }
  s.source_files     = 'Sources/Linkrunner/**/*.swift'
  s.frameworks       = 'Foundation', 'UIKit', 'Network'
  s.module_name      = 'LinkrunnerKit'

  # Google On-Device Measurement — supplies `odm_info` for Integrated Conversion
  # Measurement. Apps already on Firebase Analytics 11.14.0+ get this transitively;
  # see the GA4F compatibility table in the README before changing this constraint.
  s.dependency 'GoogleAdsOnDeviceConversion', '~> 3.6'

  # Make it a pure Swift module without Objective-C bridging
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO'
  }

  # Required by GoogleAdsOnDeviceConversion: -ObjC so the linker loads the
  # framework's Objective-C classes and categories, -lc++ for its C++ runtime.
  # These must reach the app target, not just this pod.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC -lc++'
  }
end
