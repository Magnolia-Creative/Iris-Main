import Metal
import simd

final class CompositorPipeline {
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let quadVertexBuffer: MTLBuffer

    init(metalContext: MetalContext, outputPixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        let vertexFn = metalContext.library.makeFunction(name: "compositorVertex")
        let fragmentFn = metalContext.library.makeFunction(name: "compositorFragment")

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride * 2

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.fragmentFunction = fragmentFn
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = outputPixelFormat

        // Premultiplied alpha blending
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try metalContext.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw RenderEngineError.failedToCreatePipelineState(error.localizedDescription)
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        guard let sampler = metalContext.device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RenderEngineError.failedToCreateSampler
        }
        self.samplerState = sampler

        // Full-screen quad: position (float2) + texcoord (float2) as triangle strip
        let vertices: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0,
        ]
        guard let buffer = metalContext.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw RenderEngineError.failedToCreateBuffer
        }
        self.quadVertexBuffer = buffer
    }

    struct Layer {
        let texture: MTLTexture
        let transform: matrix_float4x4
        let colorAdjustments: ColorAdjustmentsUniforms
    }

    struct CaptionLayer {
        let texture: MTLTexture
        let transform: matrix_float4x4
        let opacity: Float
    }

    func composite(
        layers: [Layer],
        captions: [CaptionLayer],
        into drawable: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        for layer in layers {
            var transform = layer.transform
            var adjustments = layer.colorAdjustments
            encoder.setVertexBytes(&transform, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
            encoder.setFragmentTexture(layer.texture, index: 0)
            encoder.setFragmentBytes(&adjustments, length: MemoryLayout<ColorAdjustmentsUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        for caption in captions {
            var transform = caption.transform
            var adjustments = ColorAdjustmentsUniforms(
                exposure: 0, contrast: 0, saturation: 0,
                highlights: 0, shadows: 0, opacity: caption.opacity
            )
            encoder.setVertexBytes(&transform, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
            encoder.setFragmentTexture(caption.texture, index: 0)
            encoder.setFragmentBytes(&adjustments, length: MemoryLayout<ColorAdjustmentsUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
    }
}
