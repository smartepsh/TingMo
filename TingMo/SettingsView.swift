import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape")
                .resizable()
                .frame(width: 40, height: 40)
            Text("TingMo Settings")
                .font(.title)
            Text("配置项将在这里显示")
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}
