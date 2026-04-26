import AppKit
import Foundation

func dbg(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    // 用最原始的 C API，不可能出错
    let fp = fopen("/tmp/sayit_debug.log", "a")
    if let fp = fp {
        fputs(line, fp)
        fflush(fp)
        fclose(fp)
    }
}

// 清空
fclose(fopen("/tmp/sayit_debug.log", "w")!)
dbg("[App] 启动")

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
