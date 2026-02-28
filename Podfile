# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

post_install do |installer|
    installer.generated_projects.each do |project|
          project.targets.each do |target|
              target.build_configurations.each do |config|
                  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
               end
          end
   end
end

target 'NovelSpeaker' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # Pods for NovelSpeaker
  pod 'SZTextView'
  pod 'Eureka'

  source 'https://github.com/CocoaPods/Specs.git'
  pod 'FTLinearActivityIndicator'
  pod 'SSZipArchive'

  #pod 'IceCream', :git => 'https://github.com/caiyue1993/IceCream.git'
  #pod 'Realm', "<= 10.7.7"
  pod 'IceCream'
  pod 'Kanna'
  pod 'Erik'
  pod 'DataCompression'

  target 'NovelSpeakerTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'NovelSpeakerWatchApp' do
    platform :watchos, '7.3'
    use_frameworks!
  end
  target 'NovelSpeakerWatchApp WatchKit App' do
    platform :watchos, '7.3'
    use_frameworks!
  end
  target 'NovelSpeakerWatchApp WatchKit Extension' do
    platform :watchos, '7.3'
    use_frameworks!
    pod 'SSZipArchive'
    pod 'IceCream'
    pod 'Kanna'
    pod 'DataCompression'
  end

end

#target 'NovelSpeakerURLDownloadExtension' do
#  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
#  use_frameworks!
#
#  # Pods for NovelSpeakerURLDownloadExtension
#
#end
