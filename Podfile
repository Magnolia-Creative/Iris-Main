source 'https://cdn.cocoapods.org/'
platform :ios, '26.2'
use_frameworks!

target 'Iris-Main' do
  pod 'VideoLab'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 12.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      end
    end
  end

  # VideoLab 0.0.1: MTAudioProcessingTapCreate out-parameter type changed in recent SDKs.
  audio_render = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Audio/AudioRenderLayer.swift')
  if File.exist?(audio_render)
    contents = File.read(audio_render)
    patched = contents.gsub(
      <<~OLD,
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        if status != noErr {
            print("Failed to create audio processing tap")
        }
        return tap?.takeRetainedValue()
      OLD
      <<~NEW
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        if status != noErr {
            print("Failed to create audio processing tap")
        }
        return tap
      NEW
    )
    File.write(audio_render, patched) if patched != contents
  end
end
