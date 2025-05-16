Pod::Spec.new do |s|
  s.name             = 'Linkrunner'
  s.version          = '1.0.0'
  s.summary          = 'AI‑powered Mobile Measurement SDK.'
  s.description      = <<-DESC
    Native Swift SDK for Linkrunner.io—attribution, event & payment tracking.
  DESC
  s.homepage         = 'https://github.com/linkrunner-labs/linkrunner-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Linkrunner' => 'darshil@linkrunner.io' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.source           = { :git => 'https://github.com/linkrunner-labs/linkrunner-ios.git', :tag => s.version }
  # --- Source distribution -----------------------------------------------
  s.source_files     = 'Sources/Linkrunner/**/*.{swift}'
  s.frameworks       = 'Foundation', 'UIKit'
  s.swift_version    = '5.9'
  # --- Binary XCFramework distribution (optional) ------------------------
  # s.vendored_frameworks = 'Binary/Linkrunner.xcframework'
  # s.pod_target_xcconfig  = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }
end
