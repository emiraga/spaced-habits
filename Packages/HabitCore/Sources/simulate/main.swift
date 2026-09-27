import Foundation
import HabitSimulation

/// Prints a 180-day table for one §4.8 synthetic user: `swift run simulate <scenario>`.
let names = Scenario.all.keys.sorted()
guard CommandLine.arguments.count == 2, let scenario = Scenario.all[CommandLine.arguments[1]] else {
    FileHandle.standardError.write(Data("usage: simulate <\(names.joined(separator: "|"))>\n".utf8))
    exit(2)
}

try print(SimulationTable.render(Simulator.run(scenario)))
