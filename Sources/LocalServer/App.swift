import SwiftUI

struct LocalServerApp: App {
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("\(store.count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
