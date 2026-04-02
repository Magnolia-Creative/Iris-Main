import Metal
import UIKit
import simd

final class CaptionRenderer {
    private let metalContext: MetalContext

    private struct CachedCaption {
        let texture: MTLTexture
        let text: String
        let fontSize: CGFloat
        let textureSize: CGSize
    }

    private var cache: [UUID: CachedCaption] = [:]

    init(metalContext: MetalContext) {
        self.metalContext = metalContext
    }

    func texture(for caption: RenderCaptionCueInput, outputSize: CGSize, displayScale: CGFloat = 2.0) -> MTLTexture? {
        if let cached = cache[caption.id],
           cached.text == caption.text,
           cached.fontSize == caption.style.fontSize {
            return cached.texture
        }

        guard let texture = renderCaptionTexture(caption, outputSize: outputSize, displayScale: displayScale) else { return nil }
        cache[caption.id] = CachedCaption(
            texture: texture,
            text: caption.text,
            fontSize: caption.style.fontSize,
            textureSize: CGSize(width: texture.width, height: texture.height)
        )
        return texture
    }

    func textureSize(for captionID: UUID) -> CGSize? {
        cache[captionID]?.textureSize
    }

    func buildTransform(
        caption: RenderCaptionCueInput,
        captionTextureSize: CGSize,
        outputSize: CGSize
    ) -> matrix_float4x4 {
        let scaleX = Float(captionTextureSize.width / outputSize.width)
        let scaleY = Float(captionTextureSize.height / outputSize.height)
        let posX = (caption.position.x - 0.5) * 2.0
        let posY = -(caption.position.y - 0.5) * 2.0

        let S = matrix_float4x4.scale(x: scaleX, y: scaleY, z: 1)
        let T = matrix_float4x4.translation(x: posX, y: posY, z: 0)
        return T * S
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Internal

    private func renderCaptionTexture(_ caption: RenderCaptionCueInput, outputSize: CGSize, displayScale: CGFloat) -> MTLTexture? {
        let scale = displayScale
        let maxWidth = outputSize.width * 0.8 * scale
        let padding = caption.style.cornerRadius * scale * 1.5

        let font = UIFont(name: "Manrope", size: caption.style.fontSize * scale)
            ?? UIFont.systemFont(ofSize: caption.style.fontSize * scale, weight: .medium)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textColor = UIColor(
            red: CGFloat(caption.style.textColor.x),
            green: CGFloat(caption.style.textColor.y),
            blue: CGFloat(caption.style.textColor.z),
            alpha: CGFloat(caption.style.textColor.w)
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        let nsText = caption.text as NSString
        let boundingRect = nsText.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        let texWidth = Int(ceil(boundingRect.width + padding * 2))
        let texHeight = Int(ceil(boundingRect.height + padding * 2))
        guard texWidth > 0, texHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: texWidth,
            height: texHeight,
            bitsPerComponent: 8,
            bytesPerRow: texWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let bgColor = UIColor(
            red: CGFloat(caption.style.backgroundColor.x),
            green: CGFloat(caption.style.backgroundColor.y),
            blue: CGFloat(caption.style.backgroundColor.z),
            alpha: CGFloat(caption.style.backgroundColor.w)
        )

        ctx.setFillColor(bgColor.cgColor)
        let bgRect = CGRect(x: 0, y: 0, width: texWidth, height: texHeight)
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: caption.style.cornerRadius * scale)
        ctx.addPath(bgPath.cgPath)
        ctx.fillPath()

        UIGraphicsPushContext(ctx)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(texHeight))
        ctx.scaleBy(x: 1, y: -1)

        let textRect = CGRect(x: padding, y: padding, width: boundingRect.width, height: boundingRect.height)
        nsText.draw(in: textRect, withAttributes: attributes)

        ctx.restoreGState()
        UIGraphicsPopContext()

        guard let cgImage = ctx.makeImage() else { return nil }
        return metalContext.textureFromCGImage(cgImage)
    }
}
