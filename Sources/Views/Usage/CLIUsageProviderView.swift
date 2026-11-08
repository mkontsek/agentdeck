import SwiftUI

struct CLIUsageProviderView: View {
    @EnvironmentObject var store: AppStore
    let profile: CLIProfile
    let snapshot: CLIUsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.name).font(.headline)
                Spacer()
                let count = store.sessions.filter { $0.kind == .cli && $0.cliProfileID == profile.id }.count
                Text("\(count) session\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            if let snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.label)
                            Spacer()
                            Text("\(window.usedPercent, specifier: "%.0f")% used").monospacedDigit()
                        }.font(.caption)
                        ProgressView(value: window.usedPercent, total: 100).tint(
                            window.usedPercent >= 90 ? .orange : .accentColor)
                        HStack {
                            Text(window.limit)
                            Spacer()
                            if let reset = window.resetsAt {
                                if reset <= Date() {
                                    Text("Reset due · awaiting update")
                                } else {
                                    Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                                }
                            } else {
                                Text("Reset not reported")
                            }
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if snapshot.windows.isEmpty {
                    Text("Usage — · Limit — · Reset —").font(.caption).foregroundStyle(.secondary)
                }
                if !snapshot.detail.isEmpty { Text(snapshot.detail).font(.caption).foregroundStyle(.secondary) }
                if let error = snapshot.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let observed = snapshot.observedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        let stale = timeline.date.timeIntervalSince(observed) > 120 || snapshot.error != nil
                        Text(
                            "\(stale ? "Stale · " : "")\(snapshot.source) · checked \(observed.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.caption2).foregroundStyle(stale ? Color.orange : .secondary)
                    }
                }
            } else {
                Text("Checking available usage…").font(.caption).foregroundStyle(.secondary)
            }
            let sessions = store.sessions.filter { $0.kind == .cli && $0.cliProfileID == profile.id }
            ForEach(sessions) { session in
                HStack {
                    Circle().fill(store.status(of: session.id).color).frame(width: 6, height: 6)
                    Button(session.name) {
                        store.selectTab(session.id)
                        store.settings.workspaceMode = .sessions
                    }.buttonStyle(.link)
                    Spacer()
                    Text(store.runtime[session.id]?.contextInfo ?? store.status(of: session.id).label).foregroundStyle(
                        .secondary)
                }.font(.caption2)
            }
            Divider()
        }
    }
}
