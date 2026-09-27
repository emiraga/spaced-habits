import Darwin
import Foundation
import os

/// Cold launch → first screen (DESIGN.md §5.3, target < 400 ms). A signpost interval for Instruments, plus
/// a log line measured from process start, so it includes dyld and store loading:
/// `log stream --predicate 'subsystem == "ga.emira.spacedhabits" && category == "launch"'`.
@MainActor
enum LaunchMetrics {
    private static let signposter = OSSignposter(subsystem: "ga.emira.spacedhabits", category: .pointsOfInterest)
    private static let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "launch")
    private static var interval: OSSignpostIntervalState?
    private static var appInit: Date?

    enum MetricsError: Error {
        case sysctlFailed(errno: Int32)
    }

    static func begin() {
        interval = signposter.beginInterval("Launch")
        appInit = Date()
    }

    /// Call when the first screen appears; only the first call counts.
    static func firstScreenAppeared() {
        guard let state = interval else { return }
        interval = nil
        signposter.endInterval("Launch", state)
        do {
            let now = Date()
            let total = try now.timeIntervalSince(processStart()) * 1000
            let ours = now.timeIntervalSince(appInit ?? now) * 1000
            logger.info("""
            First screen \(total, format: .fixed(precision: 0), privacy: .public) ms after process start, \
            \(ours, format: .fixed(precision: 0), privacy: .public) ms after App.init
            """)
        } catch {
            logger.error("Launch time unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private static func processStart() throws -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            throw MetricsError.sysctlFailed(errno: errno)
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
