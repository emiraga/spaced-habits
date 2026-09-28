import Foundation
import HabitCore
import HabitSimulation

/// `swift run simulate <scenario> [--end yyyy-MM-dd] [--json]`: prints the 180-day table for one §4.8
/// synthetic user, or with `--json` the `Truth` it produced as an export (§11), which the app imports: Settings →
/// Import, or `-importFixture <path>` in a debug build.
/// `--end` moves the run so its last day is that day (default: it starts on `Simulator.defaultStart`).
let names = Scenario.all.keys.sorted()
let usage = "usage: simulate <\(names.joined(separator: "|"))> [--end yyyy-MM-dd] [--json]\n"

func fail() -> Never {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }
var end: DayKey?
if let flag = arguments.firstIndex(of: "--end") {
    guard flag + 1 < arguments.count, let day = DayKey(arguments[flag + 1]) else { fail() }
    end = day
    arguments.removeSubrange(flag ... flag + 1)
}

guard arguments.count == 1, let scenario = Scenario.all[arguments[0]] else { fail() }

let start = end.map { $0.adding(days: 1 - scenario.days) } ?? Simulator.defaultStart
let result = try Simulator.run(scenario, start: start)
if json {
    let lastDay = start.adding(days: scenario.days - 1)
    let export = DataExport(truth: result.log, projected: result.projected, exportedAt: Simulator.noon(of: lastDay))
    try FileHandle.standardOutput.write(export.json())
} else {
    print(SimulationTable.render(result))
}
