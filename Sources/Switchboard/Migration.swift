import Foundation

/// The app used to be called LocalServer. Carry its saved servers, pins, settings and logs over, once.
enum Migration {
    static func run() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let logs = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs")
        for (old, new) in [(support.appendingPathComponent("LocalServer"), support.appendingPathComponent("Switchboard")),
                           (logs.appendingPathComponent("LocalServer"), logs.appendingPathComponent("Switchboard"))]
        where fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: "migratedFromLocalServer") == nil,
           let old = UserDefaults(suiteName: "dev.localserver.menubar")?.persistentDomain(forName: "dev.localserver.menubar") {
            for key in ["showStopped", "notifyOnStop"] where defaults.object(forKey: key) == nil {
                if let v = old[key] { defaults.set(v, forKey: key) }
            }
            defaults.set(true, forKey: "migratedFromLocalServer")
        }
    }
}
