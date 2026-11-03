Pod::Spec.new do |s|
  s.name             = 'LinkrunnerKit'
  s.version          = '5.0.0'
  s.summary          = 'Linkrunner MMP SDK for iOS: install attribution, deferred deep linking, in-app events, revenue and SKAN.'
  s.description      = <<-DESC
    Native Swift SDK for Linkrunner, the mobile measurement partner (MMP): install attribution, deferred deep linking, in-app event and revenue tracking, and SKAdNetwork conversion values.
  DESC
  s.homepage         = 'https://docs.linkrunner.io/sdk/ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Linkrunner' => 'darshil@linkrunner.io' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.source           = { :git => 'https://github.com/linkrunner-labs/linkrunner-ios.git', :tag => s.version.to_s }
  s.source_files     = 'Sources/Linkrunner/**/*.swift'
  s.frameworks       = 'Foundation', 'UIKit', 'Network'
  s.module_name      = 'LinkrunnerKit'

  # No dependency on GoogleAdsOnDeviceConversion: it is detected at runtime (see
  # ODMService), so apps that do not use Integrated Conversion Measurement are
  # unaffected. Apps that want ICM add `pod 'GoogleAdsOnDeviceConversion'` themselves,
  # or already have it via the Firebase iOS SDK. Keeping it out also avoids forcing
  # `static_framework` on every consumer, since Google ships a static binary.

  # Make it a pure Swift module without Objective-C bridging
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO'
  }

end
