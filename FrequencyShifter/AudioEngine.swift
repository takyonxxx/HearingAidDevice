import AVFoundation
import Accelerate

class AudioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var isHeadphoneConnected = false
    @Published var isPlaying = false
    @Published var outputVolume: Float = 0.5 {
        didSet {
            updateMixerVolume()
            UserDefaults.standard.set(outputVolume, forKey: "outputVolume")
        }
    }
    @Published var frequencyThreshold: Float = 10000.0 {
        didSet {
            UserDefaults.standard.set(frequencyThreshold, forKey: "frequencyThreshold")
        }
    }
    @Published var lowerFreq: Float = 20.0 {
        didSet {
            UserDefaults.standard.set(lowerFreq, forKey: "lowerFreq")
        }
    }
    @Published var upperFreq: Float = 20000.0 {
        didSet {
            UserDefaults.standard.set(upperFreq, forKey: "upperFreq")
        }
    }
    @Published var dominantFrequency: Float = 0.0  // Anlık dominant frekans (Hz)
    
    private var audioEngine: AVAudioEngine!
    private var recordedBuffer: AVAudioPCMBuffer?
    private var currentMixer: AVAudioMixerNode?
    
    private var playbackNodes: (low: AVAudioPlayerNode, high: AVAudioPlayerNode)?
    
    private let bufferSize: Int = 4096
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize = 4096
    
    private func updateMixerVolume() {
        currentMixer?.outputVolume = outputVolume
    }
    
    private func analyzeDominantFrequency(buffer: AVAudioPCMBuffer, sampleRate: Float) {
        guard let fftSetup = fftSetup,
              let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: min(frameCount, fftSize))
        
        // FFT için arrays
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        // Hamming window uygula (daha iyi frekans hassasiyeti için)
        var windowed = [Float](repeating: 0, count: fftSize)
        for i in 0..<min(frameCount, fftSize) {
            let windowValue = 0.54 - 0.46 * cos(2.0 * .pi * Float(i) / Float(fftSize - 1))
            windowed[i] = samples[i] * windowValue
        }
        
        // Input'u kopyala
        for i in 0..<fftSize {
            realIn[i] = windowed[i]
        }
        
        // FFT uygula
        realIn.withUnsafeMutableBufferPointer { realPtr in
            imagIn.withUnsafeMutableBufferPointer { imagPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        vDSP_DFT_Execute(fftSetup,
                                        realPtr.baseAddress!,
                                        imagPtr.baseAddress!,
                                        realOutPtr.baseAddress!,
                                        imagOutPtr.baseAddress!)
                    }
                }
            }
        }
        
        // Magnitude hesapla
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<fftSize / 2 {
            let real = realOut[i]
            let imag = imagOut[i]
            magnitudes[i] = sqrt(real * real + imag * imag)
        }
        
        // En yüksek magnitude'u bul (DC bileşenini atla)
        var maxMagnitude: Float = 0
        var maxIndex: Int = 0
        
        for i in 1..<fftSize / 2 {  // i=1'den başla (DC'yi atla)
            if magnitudes[i] > maxMagnitude {
                maxMagnitude = magnitudes[i]
                maxIndex = i
            }
        }
        
        // Parabolic interpolation ile daha hassas frekans tespiti
        let frequency: Float
        if maxIndex > 0 && maxIndex < (fftSize / 2 - 1) {
            let alpha = magnitudes[maxIndex - 1]
            let beta = magnitudes[maxIndex]
            let gamma = magnitudes[maxIndex + 1]
            
            let delta = 0.5 * (alpha - gamma) / (alpha - 2 * beta + gamma)
            let interpolatedIndex = Float(maxIndex) + delta
            
            frequency = interpolatedIndex * sampleRate / Float(fftSize)
        } else {
            frequency = Float(maxIndex) * sampleRate / Float(fftSize)
        }
        
        // UI'ı güncelle (sadece anlamlı değerler için)
        if maxMagnitude > 0.001 {  // Noise threshold
            DispatchQueue.main.async {
                self.dominantFrequency = frequency
            }
        }
    }
    
    init() {
        // FFT setup
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        
        // Kaydedilmiş ayarları yükle
        if UserDefaults.standard.object(forKey: "outputVolume") != nil {
            outputVolume = UserDefaults.standard.float(forKey: "outputVolume")
        }
        if UserDefaults.standard.object(forKey: "frequencyThreshold") != nil {
            frequencyThreshold = UserDefaults.standard.float(forKey: "frequencyThreshold")
        }
        if UserDefaults.standard.object(forKey: "lowerFreq") != nil {
            lowerFreq = UserDefaults.standard.float(forKey: "lowerFreq")
        }
        if UserDefaults.standard.object(forKey: "upperFreq") != nil {
            upperFreq = UserDefaults.standard.float(forKey: "upperFreq")
        }
        
        setupEngine()
        observeRouteChanges()
        
        // İlk durumu main thread'de kontrol et
        DispatchQueue.main.async { [weak self] in
            self?.checkHeadphoneConnection()
        }
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    private func setupEngine() {
        audioEngine = AVAudioEngine()
        // playerNode artık local olarak oluşturuluyor
    }
    
    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            print("🔔 Route change notification alındı")
            
            // Sadece running ise kontrol et
            if self.isRunning {
                self.checkHeadphoneConnection()
            } else {
                print("🔔 Henüz çalışmıyor, route change ignore edildi")
            }
        }
    }
    
    private func checkHeadphoneConnection() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let isConnected = route.outputs.contains { output in
            output.portType == .bluetoothA2DP ||      // Bluetooth kulaklık/speaker
            output.portType == .bluetoothHFP ||       // Bluetooth hands-free
            output.portType == .bluetoothLE ||        // Bluetooth LE
            output.portType == .headphones ||         // Kablolu kulaklık
            output.portType == .airPlay               // AirPlay/Bluetooth speaker
        }
        
        let wasConnected = self.isHeadphoneConnected
        
        // Direkt set et - main thread'de zaten çağrılıyor
        self.isHeadphoneConnected = isConnected
        
        // Sadece kulaklık ÇIKARILIRSA durdur (bağlanırsa değil)
        if wasConnected && !isConnected && isRunning {
            print("🎧 Kulaklık çıkarıldı, durduruluyor")
            stop()
        }
        
        print("🎧 Route check: wasConnected=\(wasConnected), isConnected=\(isConnected), route=\(route.outputs.map { $0.portType.rawValue })")
    }
    
    func start() {
        guard !isRunning else { 
            print("⚠️ Zaten çalışıyor")
            return 
        }
        
        print("▶️ START çağrıldı")
        checkHeadphoneConnection()
        
        // Session kurulumu
        let session = AVAudioSession.sharedInstance()
        do {
            // Bluetooth için optimize edilmiş ayarlar
            try session.setCategory(.playAndRecord, 
                                   mode: .default,
                                   options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            print("✅ Session kuruldu")
            
            // Route kontrol
            let route = session.currentRoute
            print("📱 Aktif output: \(route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        } catch {
            print("❌ Session hatası: \(error)")
            return
        }
        
        // Engine'i yeniden kur
        if audioEngine.isRunning {
            print("🔄 Eski engine durduruluyor")
            audioEngine.stop()
        }
        setupEngine()
        print("🔧 Yeni engine kuruldu")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let sampleRate = Float(inputFormat.sampleRate)
        
        print("🎤 Sample rate: \(sampleRate)")
        print("🎤 Channels: \(inputFormat.channelCount)")
        print("🎤 Format: \(inputFormat)")
        print("🎧 Kulaklık bağlı: \(isHeadphoneConnected)")
        
        if isHeadphoneConnected {
            // Gerçek zamanlı mod - hybrid sistem
            // İKİ AYRI PLAYER NODE: biri düşük, biri yüksek frekanslar için
            
            let lowPlayerNode = AVAudioPlayerNode()
            let highPlayerNode = AVAudioPlayerNode()
            
            let lowPassFilter = AVAudioUnitEQ(numberOfBands: 1)
            lowPassFilter.bands[0].filterType = .lowPass
            lowPassFilter.bands[0].frequency = frequencyThreshold  // Ayarlanabilir
            lowPassFilter.bands[0].bandwidth = 1.0
            lowPassFilter.bands[0].bypass = false
            
            let highPassFilter = AVAudioUnitEQ(numberOfBands: 1)
            highPassFilter.bands[0].filterType = .highPass
            highPassFilter.bands[0].frequency = frequencyThreshold  // Ayarlanabilir
            highPassFilter.bands[0].bandwidth = 1.0
            highPassFilter.bands[0].bypass = false
            
            let pitchShifter = AVAudioUnitTimePitch()
            pitchShifter.pitch = -1200
            
            let mixer = AVAudioMixerNode()
            mixer.outputVolume = outputVolume  // Volume kontrolü
            
            audioEngine.attach(lowPlayerNode)
            audioEngine.attach(highPlayerNode)
            audioEngine.attach(lowPassFilter)
            audioEngine.attach(highPassFilter)
            audioEngine.attach(pitchShifter)
            audioEngine.attach(mixer)
            
            // Mixer'ı kaydet (volume kontrolü için)
            currentMixer = mixer
            
            // YOL 1: lowPlayer → lowPass → mixer
            audioEngine.connect(lowPlayerNode, to: lowPassFilter, format: inputFormat)
            audioEngine.connect(lowPassFilter, to: mixer, format: inputFormat)
            
            // YOL 2: highPlayer → highPass → pitch → mixer
            audioEngine.connect(highPlayerNode, to: highPassFilter, format: inputFormat)
            audioEngine.connect(highPassFilter, to: pitchShifter, format: inputFormat)
            audioEngine.connect(pitchShifter, to: mixer, format: inputFormat)
            
            // Mixer → output
            audioEngine.connect(mixer, to: audioEngine.outputNode, format: inputFormat)
            
            inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                // Frekans analizi yap
                self.analyzeDominantFrequency(buffer: buffer, sampleRate: Float(inputFormat.sampleRate))
                // Aynı buffer'ı iki yola da gönder
                lowPlayerNode.scheduleBuffer(buffer)
                highPlayerNode.scheduleBuffer(buffer)
            }
            
            // ÖNCELİKLE engine'i başlat
            do {
                try audioEngine.start()
                print("✅ Engine başlatıldı")
                
                // SONRA player node'ları play et
                lowPlayerNode.play()
                highPlayerNode.play()
                print("✅ Player node'lar başlatıldı")
                
                DispatchQueue.main.async {
                    self.isRunning = true
                }
                
                print("✅ Gerçek zamanlı mod aktif (threshold: \(Int(self.frequencyThreshold))Hz)")
                return  // Kayıt modu kısmına gitme
            } catch {
                print("❌ Engine start hatası: \(error)")
                return
            }
        } else {
            // Kayıt modu
            // MEVCUT KAYDI KORUYORUZ - yeni start eski kayda ekler
            if recordedBuffer == nil {
                print("🔴 Yeni kayıt başlatılıyor")
            } else {
                print("🔴 Mevcut kayda devam edilecek - mevcut frame: \(recordedBuffer?.frameLength ?? 0)")
            }
            
            print("🔴 Kayıt modu - tap kuruluyor...")
            print("🔴 Buffer size: \(bufferSize)")
            
            inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                // Frekans analizi yap
                self.analyzeDominantFrequency(buffer: buffer, sampleRate: Float(inputFormat.sampleRate))
                // Kaydet
                self.recordBuffer(buffer)
            }
            
            DispatchQueue.main.async {
                // hasRecording'i koruyoruz
                self.isRecording = true
            }
            print("🔴 Kayıt modu tap kuruldu")
        }
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
            print("✅ Engine başlatıldı - isRunning: \(self.audioEngine.isRunning)")
        } catch {
            print("❌ Start hatası: \(error)")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        print("⏹️ STOP çağrıldı")
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        currentMixer = nil  // Mixer referansını temizle
        
        // Kayıt bilgisini koru
        let hadRecording = hasRecording
        if hadRecording && recordedBuffer != nil {
            print("💾 Kayıt korundu - frame: \(recordedBuffer?.frameLength ?? 0)")
        }
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.isRecording = false
            self.dominantFrequency = 0  // Frekansı sıfırla
            // hasRecording'i KORUYORUZ
        }
        
        print("✅ Durduruldu - hasRecording: \(self.hasRecording)")
    }
    
    private func recordBuffer(_ buffer: AVAudioPCMBuffer) {
        // İlk buffer için allocation
        if recordedBuffer == nil {
            let format = buffer.format
            let capacity = format.sampleRate * 60 // 60 saniye
            
            recordedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(capacity)
            )
            recordedBuffer?.frameLength = 0
            print("📼 Yeni kayıt buffer'ı oluşturuldu - capacity: \(capacity)")
        }
        
        guard let recorded = recordedBuffer else { 
            print("❌ recordedBuffer nil!")
            return 
        }
        
        guard let channelData = recorded.floatChannelData,
              let bufferData = buffer.floatChannelData else { 
            print("❌ Channel data alınamadı")
            return 
        }
        
        let frameLength = Int(buffer.frameLength)
        let currentFrames = Int(recorded.frameLength)
        let newFrameLength = currentFrames + frameLength
        
        guard newFrameLength <= recorded.frameCapacity else { 
            print("⚠️ Buffer kapasitesi doldu - current: \(currentFrames), new: \(newFrameLength), capacity: \(recorded.frameCapacity)")
            return 
        }
        
        // Her kanal için kopyala
        let channelCount = Int(recorded.format.channelCount)
        for channel in 0..<channelCount {
            let dest = channelData[channel].advanced(by: currentFrames)
            let src = bufferData[channel]
            memcpy(dest, src, frameLength * MemoryLayout<Float>.size)
        }
        
        recorded.frameLength = AVAudioFrameCount(newFrameLength)
        
        // Main thread'de güncelle
        DispatchQueue.main.async {
            self.hasRecording = true
        }
        
        // İlk buffer ve her saniyede bir log (48000 Hz * 1 saniye = 48000 frames)
        if currentFrames == 0 {
            print("✅ İlk kayıt buffer'ı alındı - frameLength: \(frameLength)")
        } else if newFrameLength % 48000 < frameLength {
            let seconds = newFrameLength / 48000
            print("📊 Kayıt devam ediyor - \(seconds) saniye - \(newFrameLength) frame")
        }
    }
    
    func playRecording() {
        // Eğer zaten çalıyorsa durdur
        if isPlaying {
            stopPlayback()
            return
        }
        
        guard let buffer = recordedBuffer, hasRecording else {
            print("❌ Kayıt yok")
            return
        }
        
        print("▶️ PLAYBACK başlatılıyor")
        print("📊 Kayıt uzunluğu: \(buffer.frameLength) frame (\(Float(buffer.frameLength) / 48000.0) saniye)")
        
        // Engine'i durdur
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Yeni engine kur
        setupEngine()
        
        // Session'ı TAMAMEN sıfırla
        let session = AVAudioSession.sharedInstance()
        do {
            // Önce deactivate
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Session kapatıldı")
            
            // Kısa bekle
            Thread.sleep(forTimeInterval: 0.1)
            
            // Bluetooth kontrolü - route'a göre karar ver
            let currentRoute = session.currentRoute
            let hasBluetoothOutput = currentRoute.outputs.contains { output in
                output.portType == .bluetoothA2DP ||
                output.portType == .bluetoothHFP ||
                output.portType == .bluetoothLE ||
                output.portType == .airPlay
            }
            
            if hasBluetoothOutput {
                // Bluetooth varsa .playback kullan
                try session.setCategory(.playback, 
                                       mode: .default, 
                                       options: [.allowBluetooth, .allowBluetoothA2DP])
                print("✅ Playback kategorisi (Bluetooth)")
            } else {
                // Bluetooth yoksa .playAndRecord + speaker override
                try session.setCategory(.playAndRecord, 
                                       mode: .default,
                                       options: [])
                print("✅ PlayAndRecord kategorisi (Speaker)")
            }
            
            // Aktive et
            try session.setActive(true, options: [])
            print("✅ Session aktif")
            
            // Bluetooth yoksa speaker'a yönlendir
            if !hasBluetoothOutput {
                try session.overrideOutputAudioPort(.speaker)
                print("✅ Speaker override aktif")
            }
            
            // Route kontrol
            let route = session.currentRoute
            print("📱 Output: \(route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        } catch {
            print("❌ Session hatası: \(error)")
            return
        }
        
        // Buffer'ı OLDUĞU GİBİ kullan - pitch shifting playback sırasında yapılacak
        let processed = buffer
        print("✅ Buffer hazır - pitch shifting playback sırasında yapılacak")
        
        // Amplitüd kontrol
        var processedMaxAmp: Float = 0
        if let channelData = processed.floatChannelData {
            let samples = UnsafeBufferPointer(start: channelData[0], count: Int(processed.frameLength))
            for sample in samples {
                processedMaxAmp = max(processedMaxAmp, abs(sample))
            }
        }
        print("🔊 Max amplitüd: \(processedMaxAmp)")
        
        if processedMaxAmp < 0.001 {
            print("⚠️ UYARI: Buffer çok sessiz! Amplitüd: \(processedMaxAmp)")
        }
        
        // HYBRID SİSTEM: İki ayrı player node ile
        
        let lowPlayerNode = AVAudioPlayerNode()
        let highPlayerNode = AVAudioPlayerNode()
        
        // 1. Düşük frekans filtresi
        let lowPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        lowPassFilter.bands[0].filterType = .lowPass
        lowPassFilter.bands[0].frequency = frequencyThreshold  // Ayarlanabilir
        lowPassFilter.bands[0].bandwidth = 1.0
        lowPassFilter.bands[0].bypass = false
        
        // 2. Yüksek frekans filtresi
        let highPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        highPassFilter.bands[0].filterType = .highPass
        highPassFilter.bands[0].frequency = frequencyThreshold  // Ayarlanabilir
        highPassFilter.bands[0].bandwidth = 1.0
        highPassFilter.bands[0].bypass = false
        
        // 3. Pitch shifter
        let pitchShifter = AVAudioUnitTimePitch()
        pitchShifter.pitch = -1200
        
        // 4. Mixer
        let mixer = AVAudioMixerNode()
        mixer.outputVolume = outputVolume  // Volume kontrolü
        
        audioEngine.attach(lowPlayerNode)
        audioEngine.attach(highPlayerNode)
        audioEngine.attach(lowPassFilter)
        audioEngine.attach(highPassFilter)
        audioEngine.attach(pitchShifter)
        audioEngine.attach(mixer)
        
        // Mixer'ı kaydet (volume kontrolü için)
        currentMixer = mixer
        
        // Node'ları kaydet (stop için)
        playbackNodes = (lowPlayerNode, highPlayerNode)
        
        let format = processed.format
        
        // YOL 1: lowPlayer → lowPass → mixer
        audioEngine.connect(lowPlayerNode, to: lowPassFilter, format: format)
        audioEngine.connect(lowPassFilter, to: mixer, format: format)
        
        // YOL 2: highPlayer → highPass → pitch → mixer
        audioEngine.connect(highPlayerNode, to: highPassFilter, format: format)
        audioEngine.connect(highPassFilter, to: pitchShifter, format: format)
        audioEngine.connect(pitchShifter, to: mixer, format: format)
        
        // Mixer → output
        audioEngine.connect(mixer, to: audioEngine.outputNode, format: format)
        
        print("✅ Audio bağlantıları kuruldu (threshold: \(Int(frequencyThreshold))Hz)")
        print("🔧 Düşük frekanslar (<\(Int(frequencyThreshold))Hz): olduğu gibi")
        print("🔧 Yüksek frekanslar (>\(Int(frequencyThreshold))Hz): -1 oktav")
        
        // Volume kontrolü
        lowPlayerNode.volume = 0.5  // Her biri 0.5 çünkü toplam 1.0 olacak
        highPlayerNode.volume = 0.5
        print("🎚️ Player volumes: 0.5 + 0.5 = 1.0")
        
        // Aynı buffer'ı iki player'a da schedule et
        lowPlayerNode.scheduleBuffer(processed) { [weak self] in
            print("✅ Low freq playback tamamlandı")
        }
        
        highPlayerNode.scheduleBuffer(processed) { [weak self] in
            print("✅ High freq playback tamamlandı")
            DispatchQueue.main.async {
                self?.isPlaying = false
                self?.audioEngine.stop()
                self?.playbackNodes = nil
                self?.currentMixer = nil
            }
        }
        
        // Başlat
        do {
            try audioEngine.start()
            print("✅ Audio engine başladı")
            
            lowPlayerNode.play()
            highPlayerNode.play()
            
            DispatchQueue.main.async {
                self.isPlaying = true
            }
            
            print("🔊 PLAYBACK BAŞLADI! (hybrid mod)")
            print("🔊 System volume: \(session.outputVolume)")
        } catch {
            print("❌ Playback start hatası: \(error)")
        }
    }
    
    func stopPlayback() {
        print("⏹️ PLAYBACK durduruluyor")
        
        if let nodes = playbackNodes {
            nodes.low.stop()
            nodes.high.stop()
        }
        
        audioEngine.stop()
        playbackNodes = nil
        currentMixer = nil  // Mixer referansını temizle
        
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        
        print("✅ Playback durduruldu")
    }
    
    func deleteRecording() {
        recordedBuffer = nil
        DispatchQueue.main.async {
            self.hasRecording = false
        }
        print("🗑️ Kayıt silindi - yeni kayıt için hazır")
    }
    
    func clearRecordingForNewSession() {
        recordedBuffer = nil
        DispatchQueue.main.async {
            self.hasRecording = false
        }
        print("🆕 Yeni kayıt oturumu başlatılıyor")
    }
    
}
