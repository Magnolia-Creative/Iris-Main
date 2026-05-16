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

        for cue in cues {
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true

            let baseSize = cue.style.fontSize
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
            textLayer.string = NSAttributedString(string: cue.text, attributes: attrs)
            let maxWidth = renderSize.width * 0.9
            let textSize = (textLayer.string as? NSAttributedString)?.boundingRect(
                with: CGSize(width: maxWidth, height: renderSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size ?? .zero

            let w = min(maxWidth, ceil(textSize.width) + cue.style.cornerRadius * 2)
            let h = ceil(textSize.height) + cue.style.cornerRadius * 2
            let posX = CGFloat(cue.position.x) * renderSize.width
            let posY = CGFloat(cue.position.y) * renderSize.height
            textLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            textLayer.position = CGPoint(x: posX, y: posY)
            textLayer.cornerRadius = cue.style.cornerRadius
            textLayer.backgroundColor = UIColor(
                red: CGFloat(bg.x),
                green: CGFloat(bg.y),
                blue: CGFloat(bg.z),
                alpha: CGFloat(bg.w)
            ).cgColor
            textLayer.opacity = 0

            let tStart = min(max(cue.startTime / duration, 0), 1)
            let tEnd = min(max(cue.endTime / duration, 0), 1)
            guard tEnd > tStart else {
                textLayer.opacity = 0
                root.addSublayer(textLayer)
                continue
            }

            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnim.duration = duration
            let op = Float(cue.opacity)
            let almostOne = 1.0 - 1e-9

            let keyTimes: [NSNumber]
            let values: [Float]
            if tStart > 1e-9 {
                if tEnd < almostOne {
                    keyTimes = [0, tStart, tEnd, 1].map(NSNumber.init(value:))
                    values = [0, op, 0, 0]
                } else {
                    keyTimes = [0, tStart, 1].map(NSNumber.init(value:))
                    values = [0, op, 0]
                }
            } else if tEnd < almostOne {
                keyTimes = [0, tEnd, 1].map(NSNumber.init(value:))
                values = [op, 0, 0]
            } else {
                let split = max(tEnd - 1e-6, 0)
                keyTimes = [0, split, 1].map(NSNumber.init(value:))
                values = [op, 0, 0]
            }

            opacityAnim.keyTimes = keyTimes
            opacityAnim.values = values
            opacityAnim.calculationMode = .discrete
            opacityAnim.beginTime = AVCoreAnimationBeginTimeAtZero
            opacityAnim.fillMode = .forwards
            opacityAnim.isRemovedOnCompletion = false

            textLayer.add(opacityAnim, forKey: "captionOpacity")
            root.addSublayer(textLayer)
        }

        return root
    }
}
