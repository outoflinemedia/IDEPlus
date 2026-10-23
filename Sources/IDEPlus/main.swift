import AppKit

let app = NSApplication.shared
if ProcessInfo.processInfo.environment["IDEPLUS_SYNTAX_REPORT"] != nil { SelfTest.syntaxReport() }
if ProcessInfo.processInfo.environment["IDEPLUS_SELFTEST"] != nil { SelfTest.runAll() }
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
