import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var audioEngine: AudioEngine
    
    @State private var frequencyThreshold: Float = 10000.0
    @State private var lowerFreq: Float = 20.0
    @State private var upperFreq: Float = 20000.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Frekans Eşiği")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(frequencyThreshold)) Hz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $frequencyThreshold, in: 5000...15000, step: 500)
                            .onChange(of: frequencyThreshold) { _, newValue in
                                audioEngine.frequencyThreshold = newValue
                            }
                    }
                    .padding(.vertical, 2)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Alt Frekans")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(lowerFreq)) Hz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $lowerFreq, in: 10...1000, step: 10)
                            .onChange(of: lowerFreq) { _, newValue in
                                audioEngine.lowerFreq = newValue
                            }
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Üst Frekans")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(upperFreq)) Hz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $upperFreq, in: 10000...40000, step: 1000)
                            .onChange(of: upperFreq) { _, newValue in
                                audioEngine.upperFreq = newValue
                            }
                    }
                    .padding(.vertical, 2)
                }
                
                Section {
                    Button("Varsayılana Dön") {
                        frequencyThreshold = 10000.0
                        lowerFreq = 20.0
                        upperFreq = 20000.0
                        audioEngine.frequencyThreshold = 10000.0
                        audioEngine.lowerFreq = 20.0
                        audioEngine.upperFreq = 20000.0
                        audioEngine.outputVolume = 0.5
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tamam") { dismiss() }
                        .font(.caption)
                }
            }
            .onAppear {
                frequencyThreshold = audioEngine.frequencyThreshold
                lowerFreq = audioEngine.lowerFreq
                upperFreq = audioEngine.upperFreq
            }
        }
    }
}
