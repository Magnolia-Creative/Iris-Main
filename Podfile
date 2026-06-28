source 'https://cdn.cocoapods.org/'
platform :ios, '26.2'
use_frameworks!

target 'Iris-Main' do
  pod 'VideoLab'

  target 'Iris-MainTests' do
    inherit! :search_paths
  end
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

  # VideoLab 0.0.1: public framework headers must use framework-style imports.
  operation_constants = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Render/Operations/OperationConstants.h')
  patch_file(
    operation_constants,
    [
      ['#import "BlendModeConstants.h"', '#import <VideoLab/BlendModeConstants.h>'],
    ]
  )

  video_lab_umbrella = File.join(installer.sandbox.root, 'Target Support Files/VideoLab/VideoLab-umbrella.h')
  patch_file(
    video_lab_umbrella,
    [
      ['#import "BlendModeConstants.h"', '#import <VideoLab/BlendModeConstants.h>'],
      ['#import "OperationConstants.h"', '#import <VideoLab/OperationConstants.h>'],
      ['#import "OperationShaderTypes.h"', '#import <VideoLab/OperationShaderTypes.h>'],
      ['#import I f<VideoLab/OperationShaderTypes.h>', '#import <VideoLab/OperationShaderTypes.h>'],
    ]
  )

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

  # VideoLab 0.0.1: LookupFilter used framebuffer fetch [[color(0)]]; sample the
  # cloned source texture at texture(0) and the LUT at texture(1) instead.
  lookup_filter_swift = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Render/Operations/LookupFilter.swift')
  patch_file(
    lookup_filter_swift,
    [
      [
        "    public init() {\n        super.init(fragmentFunctionName: \"lookupFragment\", numberOfInputs: 1)\n        \n        ({ intensity = 1.0 })()\n    }\n",
        "    public init() {\n        super.init(fragmentFunctionName: \"lookupFragment\", numberOfInputs: 2)\n        shouldInputSourceTexture = true\n        enableOutputTextureRead = false\n\n        ({ intensity = 1.0 })()\n    }\n",
      ],
    ]
  )

  lookup_filter_metal = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Render/Operations/LookupFilter.metal')
  lookup_metal_old = <<~METAL_OLD.chomp
    fragment half4 lookupFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  half4 sourceColor [[color(0)]],
                                  constant float& intensity [[ buffer(1) ]])
    {
        half4 base = sourceColor;

        half blueColor = base.b * 63.0h;

        half2 quad1;
        quad1.y = floor(floor(blueColor) / 8.0h);
        quad1.x = floor(blueColor) - (quad1.y * 8.0h);

        half2 quad2;
        quad2.y = floor(ceil(blueColor) / 8.0h);
        quad2.x = ceil(blueColor) - (quad2.y * 8.0h);

        float2 texPos1;
        texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
        texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

        float2 texPos2;
        texPos2.x = (quad2.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
        texPos2.y = (quad2.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

        constexpr sampler quadSampler3;
        half4 newColor1 = inputTexture.sample(quadSampler3, texPos1);
        constexpr sampler quadSampler4;
        half4 newColor2 = inputTexture.sample(quadSampler4, texPos2);

        half4 newColor = mix(newColor1, newColor2, fract(blueColor));
        return half4(mix(base, half4(newColor.rgb, base.w), half(intensity)));
    }
  METAL_OLD
  lookup_metal_new = <<~METAL_NEW.chomp
    fragment half4 lookupFragment(TwoInputVertexIO fragmentInput [[stage_in]],
                                  texture2d<half> sourceTexture [[texture(0)]],
                                  texture2d<half> lutTexture [[texture(1)]],
                                  constant float& intensity [[ buffer(1) ]])
    {
        constexpr sampler quadSamplerSource;
        half4 base = sourceTexture.sample(quadSamplerSource, fragmentInput.textureCoordinate);

        half blueColor = base.b * 63.0h;

        half2 quad1;
        quad1.y = floor(floor(blueColor) / 8.0h);
        quad1.x = floor(blueColor) - (quad1.y * 8.0h);

        half2 quad2;
        quad2.y = floor(ceil(blueColor) / 8.0h);
        quad2.x = ceil(blueColor) - (quad2.y * 8.0h);

        float2 texPos1;
        texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
        texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

        float2 texPos2;
        texPos2.x = (quad2.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
        texPos2.y = (quad2.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

        constexpr sampler quadSampler3;
        half4 newColor1 = lutTexture.sample(quadSampler3, texPos1);
        constexpr sampler quadSampler4;
        half4 newColor2 = lutTexture.sample(quadSampler4, texPos2);

        half4 newColor = mix(newColor1, newColor2, fract(blueColor));
        return half4(mix(base, half4(newColor.rgb, base.w), half(intensity)));
    }
  METAL_NEW
  patch_file(
    lookup_filter_metal,
    [
      [lookup_metal_old, lookup_metal_new],
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

  # VideoLab 0.0.1: AVVideoCompositing pixel buffers must be Metal/IOSurface compatible on
  # modern iOS; OpenGLES-only attributes break IOSurface-backed textures in Texture.makeTexture.
  video_compositor = File.join(installer.sandbox.root, 'VideoLab/VideoLab/Video/VideoCompositor.swift')
  patch_file(
    video_compositor,
    [
      [
        "import AVFoundation\n\nclass VideoCompositor:",
        "import AVFoundation\nimport CoreVideo\n\nclass VideoCompositor:",
      ],
      [
        "String(kCVPixelBufferOpenGLESCompatibilityKey): true]",
        "String(kCVPixelBufferMetalCompatibilityKey): true,\n         String(kCVPixelBufferIOSurfacePropertiesKey): [String: Any]()]",
      ],
      [
        "        guard let newPixelBuffer = renderContext?.newPixelBuffer() else {\n            return nil\n        }",
        "        guard let newPixelBuffer = renderContext?.newPixelBuffer() else {\n            #if DEBUG\n            print(\"[VideoLab] VideoCompositor: renderContext?.newPixelBuffer() returned nil\")\n            #endif\n            return nil\n        }",
      ],
    ]
  )

  # DEBUG-only compositor diagnostics (silent failures produced black frames).
  layer_compositor_debug = <<~'DBGHELP'.chomp
    import AVFoundation

    #if DEBUG
    private func videoLabLayerCompositorLog(_ message: String) {
        print("[VideoLab] LayerCompositor: \(message)")
    }
    #endif

    class LayerCompositor {
DBGHELP

  lc_guard_instruction_old = (<<'LC1O').chomp
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction else {
            return
        }
LC1O
  lc_guard_instruction_new = (<<'LC1N').chomp
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction else {
            #if DEBUG
            videoLabLayerCompositorLog("missing VideoCompositionInstruction")
            #endif
            return
        }
LC1N

  lc_guard_output_tex_old = (<<'LC2O').chomp
        guard let outputTexture = Texture.makeTexture(pixelBuffer: pixelBuffer) else {
            return
        }
LC2O
  lc_guard_output_tex_new = (<<'LC2N').chomp
        guard let outputTexture = Texture.makeTexture(pixelBuffer: pixelBuffer) else {
            #if DEBUG
            videoLabLayerCompositorLog("Texture.makeTexture(pixelBuffer:) failed for output pixel buffer")
            #endif
            return
        }
LC2N

  lc_guard_group_old = (<<'LC3O').chomp
            guard let groupTexture = sharedMetalRenderingDevice.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
                return
            }
LC3O
  lc_guard_group_new = (<<'LC3N').chomp
            guard let groupTexture = sharedMetalRenderingDevice.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
                #if DEBUG
                videoLabLayerCompositorLog("textureCache.requestTexture failed for layer group \(textureWidth)x\(textureHeight)")
                #endif
                return
            }
LC3N

  lc_guard_source_frame_old = (<<'LC4O').chomp
            guard let pixelBuffer = request.sourceFrame(byTrackID: videoRenderLayer.trackID) else {
                return
            }
LC4O
  lc_guard_source_frame_new = (<<'LC4N').chomp
            guard let pixelBuffer = request.sourceFrame(byTrackID: videoRenderLayer.trackID) else {
                #if DEBUG
                videoLabLayerCompositorLog("sourceFrame missing for trackID \(videoRenderLayer.trackID)")
                #endif
                return
            }
LC4N

  lc_guard_bgra_old = (<<'LC5O').chomp
            guard let videoTexture = bgraVideoTexture(from: pixelBuffer,
                                                      preferredTransform: videoRenderLayer.preferredTransform) else {
                return
            }
LC5O
  lc_guard_bgra_new = (<<'LC5N').chomp
            guard let videoTexture = bgraVideoTexture(from: pixelBuffer,
                                                      preferredTransform: videoRenderLayer.preferredTransform) else {
                #if DEBUG
                let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
                videoLabLayerCompositorLog("bgraVideoTexture failed pixelFormat=0x\(String(fmt, radix: 16))")
                #endif
                return
            }
LC5N

  lc_guard_image_clone_old = (<<'LC6O').chomp
            guard let imageTexture = cloneTexture(from: sourceTexture) else {
                return
            }
LC6O
  lc_guard_image_clone_new = (<<'LC6N').chomp
            guard let imageTexture = cloneTexture(from: sourceTexture) else {
                #if DEBUG
                videoLabLayerCompositorLog("cloneTexture failed for image source")
                #endif
                return
            }
LC6N

  lc_guard_blend_bg_old = (<<'LC7O').chomp
        guard let backgroundTexture = cloneTexture(from: outputTexture) else {
            return
        }
LC7O
  lc_guard_blend_bg_new = (<<'LC7N').chomp
        guard let backgroundTexture = cloneTexture(from: outputTexture) else {
            #if DEBUG
            videoLabLayerCompositorLog("cloneTexture failed for blend background")
            #endif
            return
        }
LC7N

  lc_guard_clone_tex_old = (<<'LC8O').chomp
        guard let cloneTexture = sharedMetalRenderingDevice.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
            return nil
        }
LC8O
  lc_guard_clone_tex_new = (<<'LC8N').chomp
        guard let cloneTexture = sharedMetalRenderingDevice.textureCache.requestTexture(width: textureWidth, height: textureHeight) else {
            #if DEBUG
            videoLabLayerCompositorLog("textureCache.requestTexture failed for clone \(textureWidth)x\(textureHeight)")
            #endif
            return nil
        }
LC8N

  patch_file(
    layer_compositor,
    [
      [
        "import AVFoundation\n\nclass LayerCompositor {",
        layer_compositor_debug,
      ],
      [lc_guard_instruction_old, lc_guard_instruction_new],
      [lc_guard_output_tex_old, lc_guard_output_tex_new],
      [lc_guard_group_old, lc_guard_group_new],
      [lc_guard_source_frame_old, lc_guard_source_frame_new],
      [lc_guard_bgra_old, lc_guard_bgra_new],
      [lc_guard_image_clone_old, lc_guard_image_clone_new],
      [lc_guard_blend_bg_old, lc_guard_blend_bg_new],
      [lc_guard_clone_tex_old, lc_guard_clone_tex_new],
    ]
  )
end
