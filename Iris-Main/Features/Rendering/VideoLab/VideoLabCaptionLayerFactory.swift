import AVFoundation
import QuartzCore
import UIKit

enum VideoLabCaptionLayerFactory {
    static func makeAnimationLayer(cues: [RenderCaptionCueInput], timelineDuration: Double, renderSize: CGSize) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: renderSize)
        root.isGeometryFlipped = true
        root.beginTime = AVCoreAnimationBeginTimeAtZero

        let duration = max(timelineDuration, 0.01)
        let styleScale = captionStyleScale(for: renderSize)

        for cue in cues {
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true

            let baseSize = max(1, cue.style.fontSize * styleScale)
            let cornerRadius = cue.style.cornerRadius * styleScale
            let font: UIFont = {
                let name = cue.style.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let named = UIFont(name: name, size: baseSize) {
                    return named
                }
                return UIFont.systemFont(ofSize: baseSize, weight: cue.style.fontWeight > 500 ? .semibold : .regular)
            }()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fg = cue.style.textColor
            let bg = cue.style.backgroundColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(
                    red: CGFloat(fg.x),
                    green: CGFloat(fg.y),
                    blue: CGFloat(fg.z),
                    alpha: CGFloat(fg.w)
                ),
                .paragraphStyle: paragraph,
            ]
            let wrapped = wrapByWordCount(cue.text, maxWordsPerLine: 8)
            textLayer.string = NSAttributedString(string: wrapped, attributes: attrs)
            let maxWidth = renderSize.width * 0.9
            let textSize = (textLayer.string as? NSAttributedString)?.boundingRect(
                with: CGSize(width: maxWidth, height: renderSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size ?? .zero

            let horizontalPadding = cornerRadius * 2
            let verticalPadding = cornerRadius
            let w = min(maxWidth, ceil(textSize.width) + horizontalPadding * 2)
            let h = ceil(textSize.height) + verticalPadding * 2
            let posX = CGFloat(cue.position.x) * renderSize.width
            let posY = CGFloat(cue.position.y) * renderSize.height
            textLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            textLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            textLayer.position = CGPoint(x: posX, y: posY)
            textLayer.cornerRadius = cornerRadius
            textLayer.backgroundColor = UIColor(
                red: CGFloat(bg.x),
                green: CGFloat(bg.y),
                blue: CGFloat(bg.z),
                alpha: CGFloat(bg.w)
            ).cgColor
            textLayer.opacity = 0

            let start = min(max(cue.startTime, 0), duration)
            let end = min(max(cue.endTime, 0), duration)
            guard end > start else {
                textLayer.opacity = 0
                root.addSublayer(textLayer)
                continue
            }

            let opacityAnim = makeOpacityAnimation(
                start: start,
                end: end,
                timelineDuration: duration,
                opacity: cue.opacity
            )

            textLayer.add(opacityAnim, forKey: "captionOpacity")
            root.addSublayer(textLayer)
        }

        return root
    }

    private static func makeOpacityAnimation(
        start: Double,
        end: Double,
        timelineDuration: Double,
        opacity: Float
    ) -> CAKeyframeAnimation {
        let duration = max(timelineDuration, 0.01)
        let clampedStart = min(max(start, 0), duration)
        let clampedEnd = min(max(end, clampedStart), duration)
        let startKey = clampedStart / duration
        let endKey = clampedEnd / duration

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = duration
        animation.calculationMode = .discrete
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false

        if startKey <= 0, endKey >= 1 {
            animation.keyTimes = [0, 1]
            animation.values = [opacity, opacity]
        } else if startKey <= 0 {
            animation.keyTimes = [0, NSNumber(value: endKey), 1]
            animation.values = [opacity, Float(0), Float(0)]
        } else if endKey >= 1 {
            animation.keyTimes = [0, NSNumber(value: startKey), 1]
            animation.values = [Float(0), opacity, opacity]
        } else {
            animation.keyTimes = [0, NSNumber(value: startKey), NSNumber(value: endKey), 1]
            animation.values = [Float(0), opacity, Float(0), Float(0)]
        }
        return animation
    }

    private static func captionStyleScale(for renderSize: CGSize) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        guard shortSide.isFinite, shortSide > 0 else { return 1 }
        return max(1, shortSide / 240)
    }

    /// Insert hard line breaks every `maxWordsPerLine` words so long cues wrap onto multiple lines.
    private static func wrapByWordCount(_ text: String, maxWordsPerLine: Int) -> String {
        guard maxWordsPerLine > 0 else { return text }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > maxWordsPerLine else { return text }
        var lines: [String] = []
        var index = 0
        while index < words.count {
            let end = min(index + maxWordsPerLine, words.count)
            lines.append(words[index..<end].joined(separator: " "))
            index = end
        }
        return lines.joined(separator: "\n")
    }
}
