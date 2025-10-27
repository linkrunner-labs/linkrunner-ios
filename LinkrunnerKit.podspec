Pod::Spec.new do |s|
  s.name             = 'LinkrunnerKit'
  s.version          = '3.4.0'
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
  
  # Make it a pure Swift module without Objective-C bridging
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'SWIFT_INSTALL_OBJC_HEADER' => 'NO'
  }
end
