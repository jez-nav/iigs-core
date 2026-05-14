import SwiftUI

struct RegisterPanel: View {
    let registers: String

    var body: some View {
        GroupBox("Registers") {
            Text(registers)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }
}
