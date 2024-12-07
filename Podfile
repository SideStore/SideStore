inhibit_all_warnings!

target 'SideStore' do
  platform :ios, '14.0'

  use_frameworks!

  # Pods for AltStore
  pod 'Nuke', '~> 10.0'
  pod 'AppCenter', '~> 5.0'
  pod 'Starscream', '~> 4.0.0'

end

target 'AltStoreCore' do
  platform :ios, '14.0'

  use_frameworks!

  # Pods for AltStoreCore
  pod 'KeychainAccess', '~> 4.2.0'
  # pod 'SemanticVersion', '~> 0.3.5'
  # Add the Swift Package using the repository URL
  # pod 'SemanticVersion', :git => 'https://github.com/SwiftPackageIndex/SemanticVersion.git', :tag => '0.4.0'


end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
    end
  end
end
