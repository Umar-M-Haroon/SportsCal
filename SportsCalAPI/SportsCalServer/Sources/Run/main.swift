import App
import Vapor
import Logging

var env = try Environment.detect()

// Parse log level from --log-level flag or LOG_LEVEL env var
let logLevelArg = env.arguments.firstIndex(of: "--log-level").flatMap { i in
    env.arguments.index(after: i) < env.arguments.endIndex ? env.arguments[env.arguments.index(after: i)] : nil
}
let logLevelString = logLevelArg ?? Environment.get("LOG_LEVEL") ?? "info"
let logLevel: Logger.Level = {
    switch logLevelString.lowercased() {
    case "trace": return .trace
    case "debug": return .debug
    case "info": return .info
    case "notice": return .notice
    case "warning": return .warning
    case "error": return .error
    case "critical": return .critical
    default: return .info
    }
}()

LoggingSystem.bootstrap { label in
    PrettyLogHandler(label: label, level: logLevel)
}

let app = try await Application.make(env)
do {
    try await configure(app)
    try await app.execute()
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    throw error
}
try await app.asyncShutdown()
