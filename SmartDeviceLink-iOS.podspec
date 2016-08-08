Pod::Spec.new do |s|

s.name         = "SmartDeviceLink-iOS"
s.version      = "4.3.0"
s.summary      = "Connect your app with cars!"
s.homepage     = "https://github.com/smartdevicelink/SmartDeviceLink-iOS"
s.license      = { :type => "New BSD", :file => "LICENSE" }
s.author       = { "SmartDeviceLink Team" => "joel@livio.io" }
s.platform     = :ios, "6.0"
s.source       = { :git => "https://github.com/smartdevicelink/sdl_ios.git", :tag => s.version.to_s }
s.source_files = "SmartDeviceLink/*.{h,m}"
s.requires_arc = true
s.resource_bundle = { 'SmartDeviceLink' => 'SmartDeviceLink/Assets/*.{xcassets, storyboard}' }

end
