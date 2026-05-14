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

  def patch_file(path, replacements)
    return unless File.exist?(path)

    contents = File.read(path)
    patched = replacements.reduce(contents) do |memo, (old, new_value)|
      memo.gsub(old, new_value)
    end
    if patched != contents
      File.chmod(0o644, path)
      File.write(path, patched)
    end
  end

  # VideoLab 0.0.1: MTAudioProcessingTapCreate out-parameter type changed in recent SDKs.
  audio_render = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Audio/AudioRenderLayer.swift')
  patch_file(
    audio_render,
    [
      [
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
      ],
    ]
  )

  # VideoLab 0.0.1: framebuffer fetch via [[color(0)]] is rejected on some
  # current Metal compiler/device combinations. Blend against an explicit
  # background texture instead of reading from the render target.
  blend_operation_metal = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Render/Operations/BlendOperation.metal')
  patch_file(
    blend_operation_metal,
    [
      [
      <<~OLD,
        vertex SingleInputVertexIO blendOperationVertex(const device packed_float2 *position [[ buffer(0) ]],
                                                        const device packed_float2 *texturecoord [[ buffer(1) ]],
                                                        constant float4x4& modelView [[ buffer(2) ]],
                                                        constant float4x4& projection [[ buffer(3) ]],
                                                        uint vid [[vertex_id]])
        {
            SingleInputVertexIO outputVertices;
            
            outputVertices.position = projection * modelView * float4(position[vid], 0, 1.0);
            outputVertices.textureCoordinate = texturecoord[vid];
            
            return outputVertices;
        }
      OLD
      <<~NEW
        struct BlendVertexIO
        {
            float4 position [[position]];
            float2 textureCoordinate [[user(texturecoord)]];
            float2 backgroundTextureCoordinate [[user(backgroundTexturecoord)]];
        };

        vertex BlendVertexIO blendOperationVertex(const device packed_float2 *position [[ buffer(0) ]],
                                                  const device packed_float2 *texturecoord [[ buffer(1) ]],
                                                  const device packed_float2 *backgroundTexturecoord [[ buffer(2) ]],
                                                  constant float4x4& modelView [[ buffer(3) ]],
                                                  constant float4x4& projection [[ buffer(4) ]],
                                                  uint vid [[vertex_id]])
        {
            BlendVertexIO outputVertices;
            
            outputVertices.position = projection * modelView * float4(position[vid], 0, 1.0);
            outputVertices.textureCoordinate = texturecoord[vid];
            outputVertices.backgroundTextureCoordinate = backgroundTexturecoord[vid];
            
            return outputVertices;
        }
      NEW
      ],
      [
      <<~OLD,
        fragment half4 blendOperationFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                              texture2d<half> inputTexture [[texture(0)]],
                                              half4 backColor [[color(0)]],
                                              constant int& blendMode [[ buffer(1) ]],
                                              constant float& blendOpacity [[ buffer(2) ]])
        {
            constexpr sampler quadSampler;
            half4 sourceColor = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
      OLD
      <<~NEW
        fragment half4 blendOperationFragment(BlendVertexIO fragmentInput [[stage_in]],
                                              texture2d<half> inputTexture [[texture(0)]],
                                              texture2d<half> backgroundTexture [[texture(1)]],
                                              constant int& blendMode [[ buffer(1) ]],
                                              constant float& blendOpacity [[ buffer(2) ]])
        {
            constexpr sampler quadSampler;
            half4 sourceColor = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
            half4 backColor = backgroundTexture.sample(quadSampler, fragmentInput.backgroundTextureCoordinate);
      NEW
      ],
    ]
  )

  blend_operation_swift = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Render/Operations/BlendOperation.swift')
  patch_file(
    blend_operation_swift,
    [
      [
        'super.init(vertexFunctionName: "blendOperationVertex", fragmentFunctionName: "blendOperationFragment", numberOfInputs: 1)',
        'super.init(vertexFunctionName: "blendOperationVertex", fragmentFunctionName: "blendOperationFragment", numberOfInputs: 2)',
      ],
    ]
  )

  layer_compositor = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Video/LayerCompositor.swift')
  layer_compositor_blend_body = "        \n" + <<'SWIFT'.chomp
        // Render. Avoid framebuffer fetch in BlendOperation by passing the
        // current output as a normal texture input.
        guard let backgroundTexture = cloneTexture(from: outputTexture) else {
            return
        }
        defer {
            backgroundTexture.unlock()
        }

        if !enableOutputTextureRead {
            Texture.clearTexture(backgroundTexture)
        }

        blendOperation.enableOutputTextureRead = false
        blendOperation.addTexture(texture, at: 0)
        blendOperation.addTexture(backgroundTexture, at: 1)
        blendOperation.renderTexture(outputTexture)
SWIFT
  layer_compositor_broken_body = "        \n" + <<'BROKEN'.chomp
// Render. Avoid framebuffer fetch in BlendOperation by passing the
// current output as a normal texture input.
guard let backgroundTexture = cloneTexture(from: outputTexture) else {
    return
}
defer {
    backgroundTexture.unlock()
}

if !enableOutputTextureRead {
    Texture.clearTexture(backgroundTexture)
}

blendOperation.enableOutputTextureRead = false
blendOperation.addTexture(texture, at: 0)
blendOperation.addTexture(backgroundTexture, at: 1)
blendOperation.renderTexture(outputTexture)
BROKEN
  patch_file(
    layer_compositor,
    [
      [
        "        // Render\n        blendOperation.enableOutputTextureRead = enableOutputTextureRead\n        blendOperation.addTexture(texture, at: 0)\n        blendOperation.renderTexture(outputTexture)",
        layer_compositor_blend_body.chomp,
      ],
      [
        layer_compositor_broken_body.chomp,
        layer_compositor_blend_body.chomp,
      ],
    ]
  )
end
