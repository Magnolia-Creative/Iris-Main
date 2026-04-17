import Metal
import MetalKit
import CoreVideo
import os
import simd

enum RenderEngineError: Error, LocalizedError {
    case noMetalDevice
    case failedToCreateCommandQueue
    case failedToCompileShaders(String)
    case failedToCreatePipelineState(String)
    case failedToCreateSampler
    case failedToCreateBuffer
    case failedToCreateTexture
    case failedToDecodeFrame

    var errorDescription: String? {
        switch self {
        case .noMetalDevice: return "Metal is not available on this device."
        case .failedToCreateCommandQueue: return "Could not create Metal command queue."
        case .failedToCompileShaders(let msg): return "Shader compilation failed: \(msg)"
        case .failedToCreatePipelineState(let msg): return "Pipeline state creation failed: \(msg)"
        case .failedToCreateSampler: return "Could not create texture sampler."
        case .failedToCreateBuffer: return "Could not create vertex buffer."
        case .failedToCreateTexture: return "Could not create texture."
        case .failedToDecodeFrame: return "Could not decode video frame."
        }
    }
}

final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    private var metalTextureCache: CVMetalTextureCache?

    #if DEBUG
    private static let logger = Logger(subsystem: "Iris-Main", category: "Render.MetalContext")
    #endif

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderEngineError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw RenderEngineError.failedToCreateCommandQueue
        }

        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary(),
           defaultLib.functionNames.contains("compositorVertex") {
            library = defaultLib
        } else {
            do {
                library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            } catch {
                throw RenderEngineError.failedToCompileShaders(error.localizedDescription)
            }
        }

        self.device = device
        self.commandQueue = queue
        self.library = library

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.metalTextureCache = cache
    }

    func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm, usage: MTLTextureUsage = .shaderRead) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    struct BackedTexture {
        let texture: MTLTexture
        let backing: Any?
    }

    func textureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> BackedTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let pixelFormatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let texturePixelFormat: MTLPixelFormat = .bgra8Unorm

        if let cache = metalTextureCache {
            var cvTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                texturePixelFormat,
                width,
                height,
                0,
                &cvTexture
            )
            if status == kCVReturnSuccess,
               let cvTex = cvTexture,
               let texture = CVMetalTextureGetTexture(cvTex) {
                return BackedTexture(texture: texture, backing: cvTex)
            }

            #if DEBUG
            Self.logger.error(
                "pixel buffer wrap failed status=\(status) size=\(width)x\(height) format=\(pixelFormatType)"
            )
            #endif
        }

        guard pixelFormatType == kCVPixelFormatType_32BGRA else {
            #if DEBUG
            Self.logger.error(
                "pixel buffer fallback unsupported format=\(pixelFormatType) size=\(width)x\(height)"
            )
            #endif
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            #if DEBUG
            Self.logger.error(
                "pixel buffer fallback missing base address size=\(width)x\(height) format=\(pixelFormatType)"
            )
            #endif
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let texture = makeTexture(width: width, height: height, pixelFormat: texturePixelFormat) else {
            return nil
        }

        texture.replace(
            region: MTLRegion(origin: .init(), size: .init(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )

        #if DEBUG
        Self.logger.debug(
            "pixel buffer fallback upload size=\(width)x\(height) format=\(pixelFormatType) bytes_per_row=\(bytesPerRow)"
        )
        #endif

        return BackedTexture(texture: texture, backing: nil)
    }

    func textureFromCGImage(_ image: CGImage) -> MTLTexture? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        guard let texture = makeTexture(width: width, height: height, pixelFormat: .rgba8Unorm) else { return nil }
        texture.replace(
            region: MTLRegion(origin: .init(), size: .init(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )
        return texture
    }
}

// MARK: - Shader Source (runtime compilation fallback)

extension MetalContext {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct ColorAdjustments {
        float exposure;
        float contrast;
        float saturation;
        float highlights;
        float shadows;
        float opacity;
    };

    vertex VertexOut compositorVertex(
        VertexIn in [[stage_in]],
        constant float4x4 &transform [[buffer(1)]]
    ) {
        VertexOut out;
        out.position = transform * float4(in.position, 0.0, 1.0);
        out.texCoord = in.texCoord;
        return out;
    }

    fragment float4 compositorFragment(
        VertexOut in [[stage_in]],
        texture2d<float> sourceTexture [[texture(0)]],
        sampler textureSampler [[sampler(0)]],
        constant ColorAdjustments &adjustments [[buffer(0)]]
    ) {
        float4 color = sourceTexture.sample(textureSampler, in.texCoord);

        float alpha = color.a;
        if (alpha < 0.001) {
            return float4(0.0);
        }

        float3 rgb = color.rgb / alpha;

        rgb *= pow(2.0, adjustments.exposure);

        rgb = ((rgb - 0.5) * (1.0 + adjustments.contrast)) + 0.5;

        float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        rgb = mix(float3(luminance), rgb, 1.0 + adjustments.saturation);

        float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        float highlightWeight = smoothstep(0.5, 1.0, lum);
        float shadowWeight = 1.0 - smoothstep(0.0, 0.5, lum);
        rgb += adjustments.highlights * highlightWeight;
        rgb += adjustments.shadows * shadowWeight;

        rgb = clamp(rgb, 0.0, 1.0);

        float finalAlpha = alpha * adjustments.opacity;
        return float4(rgb * finalAlpha, finalAlpha);
    }
    """
}

// MARK: - Matrix Helpers

extension matrix_float4x4 {
    static func translation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(x, y, z, 1)
        return m
    }

    static func scale(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = x
        m.columns.1.y = y
        m.columns.2.z = z
        return m
    }

    static func rotationZ(angle: Float) -> matrix_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        var m = matrix_identity_float4x4
        m.columns.0.x = c
        m.columns.0.y = s
        m.columns.1.x = -s
        m.columns.1.y = c
        return m
    }
}

// MARK: - GPU-matched uniform struct

struct ColorAdjustmentsUniforms {
    var exposure: Float
    var contrast: Float
    var saturation: Float
    var highlights: Float
    var shadows: Float
    var opacity: Float
}
