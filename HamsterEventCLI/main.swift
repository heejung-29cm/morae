import Foundation
import MoraeCore

if CommandLine.arguments.contains("--smoke-test") {
    print(MoraeRuntime.smokeMessage)
} else {
    HamsterEventCommand().run(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
}
