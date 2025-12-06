import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PrompterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your text")
                .font(.headline)

            TextEditor(text: $viewModel.text)
                .font(.system(size: 14))
                .frame(minHeight: 100, maxHeight: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Text("Speed")
                Slider(value: $viewModel.speed, in: 1...40, step: 1)
                Text("\(Int(viewModel.speed)) pt/s")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }

            HStack {
                Text("Text size")
                Slider(value: $viewModel.fontSize, in: 8...30, step: 1)
                Text("\(Int(viewModel.fontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Pause prompter on mouse hover", isOn: $viewModel.pauseOnHover)
//                    Toggle("Play on detected audio", isOn: $viewModel.playOnAudio)
            }
            .toggleStyle(.switch)
            
            HStack {
                Button(action: { viewModel.isPlaying.toggle() }) {
                    Label(viewModel.isPlaying ? "Pause" : "Play",
                          systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("NotchPrompter Settings")
    }
}
