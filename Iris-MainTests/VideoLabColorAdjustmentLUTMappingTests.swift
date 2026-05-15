import Foundation
import simd
import Testing
@testable import Iris_Main

struct VideoLabColorAdjustmentLUTMappingTests {
    @Test func neutralMappingLeavesMidGray() {
        let adj = RenderColorAdjustmentsInput.neutral
        let mid = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = VideoLabColorAdjustmentLUTCore.mapRGB(mid, adjustments: adj)
        #expect(abs(out.x - 0.5) < 0.001)
        #expect(abs(out.y - 0.5) < 0.001)
        #expect(abs(out.z - 0.5) < 0.001)
    }

    @Test func brightnessRaisesLuminance() {
        var adj = RenderColorAdjustmentsInput.neutral
        adj.brightness = 0.4
        let mid = SIMD3<Float>(0.4, 0.4, 0.4)
        let out = VideoLabColorAdjustmentLUTCore.mapRGB(mid, adjustments: adj)
        let inL = simd_dot(mid, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        let outL = simd_dot(out, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        #expect(outL > inL)
    }

    @Test func exposureScalesUp() {
        var adj = RenderColorAdjustmentsInput.neutral
        adj.exposure = 0.5
        let c = SIMD3<Float>(0.25, 0.25, 0.25)
        let out = VideoLabColorAdjustmentLUTCore.mapRGB(c, adjustments: adj)
        #expect(simd_reduce_max(out) > simd_reduce_max(c))
    }

    @Test func saturationNegativeDesaturatesTowardGray() {
        var adj = RenderColorAdjustmentsInput.neutral
        adj.saturation = -1.0
        let red = SIMD3<Float>(0.9, 0.2, 0.1)
        let out = VideoLabColorAdjustmentLUTCore.mapRGB(red, adjustments: adj)
        #expect(abs(out.x - out.y) < 0.02)
        #expect(abs(out.y - out.z) < 0.02)
    }

    @Test func temperatureShiftsRedVersusBlue() {
        var warm = RenderColorAdjustmentsInput.neutral
        warm.temperature = 0.6
        var cool = RenderColorAdjustmentsInput.neutral
        cool.temperature = -0.6
        let gray = SIMD3<Float>(0.5, 0.5, 0.5)
        let w = VideoLabColorAdjustmentLUTCore.mapRGB(gray, adjustments: warm)
        let c = VideoLabColorAdjustmentLUTCore.mapRGB(gray, adjustments: cool)
        #expect(w.x > c.x)
        #expect(w.z < c.z)
    }

    @Test func cacheKeyQuantizesNearbyValues() {
        var a = RenderColorAdjustmentsInput.neutral
        a.brightness = 0.10001
        var b = RenderColorAdjustmentsInput.neutral
        b.brightness = 0.10002
        #expect(VideoLabColorAdjustmentLUTCore.cacheKey(for: a) == VideoLabColorAdjustmentLUTCore.cacheKey(for: b))
    }

    /// Identity path: neutral adjustments → LUT texels match `mapRGB` (same as linear input for mid cube).
    @Test func neutralLUTBGRABytesMatchMapRGB() {
        let adj = RenderColorAdjustmentsInput.neutral
        let data = VideoLabColorAdjustmentLUTCore.makeLUTBGRA8PixelData(for: adj)
        #expect(data.count == 512 * 512 * 4)

        func assertCell(r: Int, g: Int, b: Int) {
            let rin = Float(r) / 63.0
            let gin = Float(g) / 63.0
            let bin = Float(b) / 63.0
            let expected = VideoLabColorAdjustmentLUTCore.mapRGB(SIMD3(rin, gin, bin), adjustments: adj)
            let tileX = b % 8
            let tileY = b / 8
            let px = tileX * 64 + r
            let py = tileY * 64 + g
            let o = (py * 512 + px) * 4
            let bByte = Float(data[o]) / 255.0
            let gByte = Float(data[o + 1]) / 255.0
            let rByte = Float(data[o + 2]) / 255.0
            #expect(abs(rByte - expected.x) < 0.02)
            #expect(abs(gByte - expected.y) < 0.02)
            #expect(abs(bByte - expected.z) < 0.02)
            #expect(data[o + 3] == 255)
        }

        assertCell(r: 0, g: 0, b: 0)
        assertCell(r: 63, g: 63, b: 63)
        assertCell(r: 10, g: 20, b: 5)
        assertCell(r: 31, g: 31, b: 31)
    }

    /// After LUT encoding fix, small slider moves should not explode `mapRGB` on gray.
    @Test func smallTemperatureChangeIsSubtleOnMidGray() {
        var adj = RenderColorAdjustmentsInput.neutral
        adj.temperature = 0.05
        let gray = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = VideoLabColorAdjustmentLUTCore.mapRGB(gray, adjustments: adj)
        let delta = simd_length(out - gray)
        #expect(delta < 0.02)
    }
}
