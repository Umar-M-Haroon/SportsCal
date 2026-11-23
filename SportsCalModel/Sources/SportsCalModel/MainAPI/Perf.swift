//
//  Perf.swift
//  SportsCalModel
//
//  Signposts for the performance budgets. They show up in Instruments under
//  Points of Interest (subsystem com.KomodoLLC.SportsCal), and cost almost
//  nothing when no trace is recording. Launch the binary with SCORELINE_PERF=1
//  to also print each interval and moment to stdout, timed from process start
//  (scripts/perf_launch.sh reads those lines).
//
//  Budgets (Release, warm launch, M-series Mac / recent iPhone):
//  - launch → board visible: 300 ms
//  - filter pass (`filterSports`): 16 ms, and never on a tap's critical path
//  - tap → game detail shown: 100 ms
//

#if canImport(os)
import Foundation
import os

public enum Perf {
    public static let signposter = OSSignposter(subsystem: "com.KomodoLLC.SportsCal", category: .pointsOfInterest)

    /// SCORELINE_PERF=1 in the environment: print intervals and moments too.
    public static let printsTimings = ProcessInfo.processInfo.environment["SCORELINE_PERF"] != nil

    /// Runs `body` inside a named interval.
    public static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let token = begin(name)
        defer { end(name, token) }
        return try body()
    }

    public struct Token {
        let state: OSSignpostIntervalState
        let start: UInt64
    }

    public static func begin(_ name: StaticString) -> Token {
        Token(state: signposter.beginInterval(name, id: signposter.makeSignpostID()),
              start: DispatchTime.now().uptimeNanoseconds)
    }

    public static func end(_ name: StaticString, _ token: Token) {
        signposter.endInterval(name, token.state)
        guard printsTimings else { return }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - token.start) / 1e6
        emit(String(format: "PERF interval %@ %.1fms at %.0fms", "\(name)", duration, sinceLaunch(token.start)))
    }

    /// A one-off moment, e.g. the first frame with games on screen.
    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
        guard printsTimings else { return }
        emit(String(format: "PERF event %@ at %.0fms", "\(name)", sinceLaunch(DispatchTime.now().uptimeNanoseconds)))
    }

    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Milliseconds from process start to `uptime` (nanoseconds since boot).
    private static func sinceLaunch(_ uptime: UInt64) -> Double {
        Double(uptime - processStartUptime) / 1e6
    }

    /// Process start, converted to the same uptime clock as `DispatchTime`.
    private static let processStartUptime: UInt64 = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return DispatchTime.now().uptimeNanoseconds }
        let start = info.kp_proc.p_un.__p_starttime
        let startWall = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
        let elapsed = Date().timeIntervalSince1970 - startWall
        return DispatchTime.now().uptimeNanoseconds - UInt64(max(elapsed, 0) * 1e9)
    }()
}
#endif
