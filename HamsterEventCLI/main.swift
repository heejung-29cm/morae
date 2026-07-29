import Foundation
import MoraeCore

if CommandLine.arguments.contains("--smoke-test") {
    print(MoraeRuntime.smokeMessage)
}
