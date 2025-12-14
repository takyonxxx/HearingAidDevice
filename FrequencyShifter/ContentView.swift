import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // ScrollView - TAM EKRAN
            ScrollView {
                VStack(spacing: 8) {
                    // Icon
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(audioEngine.isRunning ? .green : .blue)
                        .symbolEffect(.pulse, isActive: audioEngine.isRunning)
                        .padding(.horizontal, 12)
                        .padding(.top, 38)  // Toolbar için
                        
                        // FREKANS GÖSTERGESİ
                        if audioEngine.isRunning {
                            VStack(spacing: 3) {
                                Text("Anlık Frekans")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    if audioEngine.dominantFrequency >= 1000 {
                                        Text(String(format: "%.2f", audioEngine.dominantFrequency / 1000.0))
                                            .font(.system(size: 36, weight: .bold, design: .rounded))
                                            .foregroundColor(.cyan)
                                            .monospacedDigit()
                                        Text("kHz")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.cyan.opacity(0.7))
                                    } else {
                                        Text(String(format: "%.0f", audioEngine.dominantFrequency))
                                            .font(.system(size: 36, weight: .bold, design: .rounded))
                                            .foregroundColor(.cyan)
                                            .monospacedDigit()
                                        Text("Hz")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.cyan.opacity(0.7))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.cyan.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.cyan.opacity(0.3), lineWidth: 1.5)
                                        )
                                )
                            }
                            .padding(.horizontal, 12)
                        }
                    
                    VStack(spacing: 4) {
                        StatusRow(
                            icon: audioEngine.isHeadphoneConnected ? "headphones" : "speaker.wave.2.fill",
                            text: audioEngine.isHeadphoneConnected ? "Kulaklık Bağlı" : "Kulaklık Yok",
                            color: audioEngine.isHeadphoneConnected ? .green : .orange
                        )
                        StatusRow(
                            icon: "mic.fill",
                            text: audioEngine.isRunning ? "Dinleniyor" : "Durduruldu",
                            color: audioEngine.isRunning ? .green : .gray
                        )
                        if audioEngine.isRecording {
                            StatusRow(icon: "record.circle.fill", text: "Kaydediliyor", color: .red)
                        }
                        if audioEngine.isPlaying {
                            StatusRow(icon: "waveform", text: "Oynatılıyor", color: .green)
                        }
                        if audioEngine.hasRecording && !audioEngine.isRunning && !audioEngine.isPlaying {
                            StatusRow(icon: "checkmark.circle.fill", text: "Kayıt Hazır", color: .blue)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    
                    // SES SEVİYESİ
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundColor(.white)
                                .font(.caption2)
                            Text("Ses Seviyesi")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(audioEngine.outputVolume * 100))%")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.1.fill")
                                .foregroundColor(.gray)
                                .font(.caption2)
                            
                            Slider(value: $audioEngine.outputVolume, in: 0...1)
                                .accentColor(.blue)
                            
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundColor(.white)
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    
                    // BUTONLAR
                    VStack(spacing: 5) {
                        if audioEngine.isHeadphoneConnected {
                            Button(action: {
                                if audioEngine.isRunning {
                                    audioEngine.stop()
                                } else {
                                    audioEngine.start()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                                        .font(.callout)
                                    Text(audioEngine.isRunning ? "Durdur" : "Başlat")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(audioEngine.isRunning ? Color.red : Color.green)
                                .cornerRadius(8)
                            }
                        } else {
                            Button(action: {
                                if audioEngine.isRunning {
                                    audioEngine.stop()
                                } else {
                                    audioEngine.start()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: audioEngine.isRunning ? "stop.fill" : "record.circle.fill")
                                        .font(.callout)
                                    Text(audioEngine.isRunning ? "Kaydı Durdur" : "Kayda Başla")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(audioEngine.isRunning ? Color.red : Color.blue)
                                .cornerRadius(8)
                            }
                            
                            if audioEngine.hasRecording && !audioEngine.isRunning {
                                HStack(spacing: 5) {
                                    Button(action: { audioEngine.playRecording() }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: audioEngine.isPlaying ? "stop.fill" : "play.fill")
                                                .font(.callout)
                                            Text(audioEngine.isPlaying ? "Durdur" : "Dinle")
                                                .font(.callout)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(audioEngine.isPlaying ? Color.red : Color.green)
                                        .cornerRadius(8)
                                    }
                                    Button(action: { 
                                        audioEngine.deleteRecording() 
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "trash.fill")
                                                .font(.callout)
                                            Text("Sil")
                                                .font(.callout)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.red)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 20)  // Alt boşluk
            }
            .edgesIgnoringSafeArea(.all)  // Tam ekran
            
            // Toolbar - OVERLAY (üstte sabit)
            VStack {
                HStack {
                    Text("Frekans Kaydırıcı")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.95))
                
                Spacer()
            }
            .edgesIgnoringSafeArea(.top)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(audioEngine: audioEngine)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

struct StatusRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
        }
    }
}
