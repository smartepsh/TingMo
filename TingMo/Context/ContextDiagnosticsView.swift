import SwiftUI

struct ContextDiagnosticsView: View {
    let diagnostics: ContextDiagnostics?
    let onRefresh: () -> Void
    
    var body: some View {
        if let diagnostics {
            VStack(alignment: .leading, spacing: 12) {
                diagnosticSection(title: "Raw Context (\(diagnostics.rawItems.count) items)", items: diagnostics.rawItems)
                Divider()
                diagnosticSection(title: "Final Context (\(diagnostics.finalItems.count) items)", items: diagnostics.finalItems)
                budgetBar(used: diagnostics.usedBudget, total: diagnostics.totalBudget)
                Button("Refresh", action: onRefresh)
            }
        } else {
            Text("No diagnostics available. Enable logging and record audio.")
                .foregroundStyle(.secondary)
        }
    }
    
    private func diagnosticSection(title: String, items: [ContextDiagnosticItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            ForEach(items) { item in
                HStack {
                    statusIcon(for: item)
                    Text(item.kind.rawValue)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("P=\(item.priority)")
                        .foregroundStyle(.secondary)
                    Text("\(item.characterCount) chars")
                        .foregroundStyle(.secondary)
                    if item.isTruncated {
                        Text("truncated")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
    
    private func statusIcon(for item: ContextDiagnosticItem) -> some View {
        Group {
            if item.isFiltered {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            } else if item.isTruncated {
                Image(systemName: "scissors")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 16)
    }
    
    private func budgetBar(used: Int, total: Int) -> some View {
        VStack(alignment: .leading) {
            Text("Budget: \(used)/\(total) chars")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(used), total: Double(total))
        }
    }
}
