#
# CocoaPods spec for the payriff Flutter plugin (iOS). Swift Package Manager uses
# payriff/Package.swift with the same sources.
#
Pod::Spec.new do |s|
  s.name             = 'payriff'
  s.version          = '1.0.0'
  s.summary          = 'Payriff payments for Flutter: native card encryption and screen protection.'
  s.description      = <<-DESC
Native half of the payriff Flutter plugin: card encryption (CryptoKit AES-GCM and
RSA-OAEP-SHA256), the X-Client-App-Id value, screen protection, external launches and
the removal of 3-D Secure website data.
                       DESC
  s.homepage         = 'https://payriff.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Payriff'
  s.source           = { :path => '.' }
  s.source_files     = 'payriff/Sources/payriff/**/*.swift'
  s.resource_bundles = { 'payriff_privacy' => ['payriff/Sources/payriff/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'CryptoKit', 'Security', 'UIKit', 'WebKit'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
