import Foundation

struct TimeFormatter {
    static func formatTime(_ microseconds: Int64) -> String {
        let totalSeconds = microseconds / 1_000_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func calcCentiSeconds(_ microseconds: Int64) -> String {
        let totalCentiseconds = microseconds / 10_000
        return String(format: "%02d", totalCentiseconds % 100)
    }

    static func formatTimeLong(_ microseconds: Int64) -> String {
        let totalSeconds = microseconds / 1_000_000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
