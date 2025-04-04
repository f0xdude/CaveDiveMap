import SwiftUI
import AVFoundation
import Accelerate

enum ClickDetectorMode {
    case calibrating
    case detecting
}

struct AudioOdometer: View {
    @StateObject private var clickDetector = SimpleClickDetector()

    var body: some View {
        VStack(spacing: 20) {
            if clickDetector.isListening {
                // If countdown is running, show it.
                if clickDetector.countdown > 0 {
                    Text("Calibration starts in: \(clickDetector.countdown) seconds")
                        .font(.headline)
                } else if clickDetector.mode == .calibrating {
                    Text("Calibrating... (\(clickDetector.calibrationCount)/\(clickDetector.requiredCalibrationCount))")
                        .font(.headline)
                } else {
                    Text("Clicks detected: \(clickDetector.clickCount)")
                        .font(.largeTitle)
                }
                
                Button("Stop") {
                    clickDetector.stopListening()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            } else {
                Button("Start") {
                    clickDetector.startListening()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .onDisappear {
            clickDetector.stopListening()
        }
    }
}

class SimpleClickDetector: ObservableObject {
    @Published var clickCount = 0
    @Published var isListening = false
    @Published var mode: ClickDetectorMode = .calibrating
    @Published var calibrationCount: Int = 0
    @Published var countdown: Int = 0  // countdown seconds visible in UI
    
    let requiredCalibrationCount = 5
    let similarityThreshold: Float = 0.8  // Adjust threshold as needed

    private let audioEngine = AVAudioEngine()
    private var calibrationSamples: [[Float]] = []
    private var countdownTimer: Timer?

    func startListening() {
        guard !isListening else { return }
        
        // Reset state when starting
        clickCount = 0
        calibrationSamples = []
        calibrationCount = 0
        mode = .calibrating
        
        // Set countdown to 5 seconds and mark listening as active
        countdown = 5
        isListening = true
        
        // Start a countdown timer that updates the countdown every second.
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.countdown > 0 {
                self.countdown -= 1
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                // After the countdown finishes, set up the audio engine tap.
                self.setupAudioEngineTap()
            }
        }
    }
    
    func stopListening() {
        if isListening {
            // Invalidate countdown timer if it's still running.
            countdownTimer?.invalidate()
            countdownTimer = nil
            
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            DispatchQueue.main.async {
                self.isListening = false
                self.countdown = 0
            }
        }
    }
    
    private func setupAudioEngineTap() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            self.processBuffer(buffer)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            try audioEngine.start()
            print("Audio engine started and tap installed")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Filter out low-level noise.
        let maxAmplitude = (0..<frameLength).reduce(0) { max($0, abs(channelData[$1])) }
        if maxAmplitude < 0.2  { return }
        
        // Extract features from the current buffer (normalized FFT magnitude spectrum)
        let features = extractFeatures(from: buffer)
        
        if mode == .calibrating {
            // Record a calibration sample.
            calibrationSamples.append(features)
            DispatchQueue.main.async {
                self.calibrationCount = self.calibrationSamples.count
                print("Calibration sample recorded: \(self.calibrationCount)/\(self.requiredCalibrationCount)")
                if self.calibrationSamples.count >= self.requiredCalibrationCount {
                    self.mode = .detecting
                    print("Calibration complete. Switching to detection mode.")
                }
            }
        } else if mode == .detecting {
            // Compare current features with calibration samples.
            let similarity = compareFeatures(features)
            if similarity > similarityThreshold {
                DispatchQueue.main.async {
                    self.clickCount += 1
                    print("Click detected with similarity: \(similarity)")
                }
            }
        }
    }
    
    private func extractFeatures(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let n = Int(buffer.frameLength)
        let log2n = vDSP_Length(log2(Double(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        
        // Copy the audio samples into an array
        var window = [Float](repeating: 0.0, count: n)
        for i in 0..<n {
            window[i] = channelData[i]
        }
        
        // Apply a Hann window to reduce spectral leakage
        var hannWindow = [Float](repeating: 0.0, count: n)
        vDSP_hann_window(&hannWindow, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(window, 1, hannWindow, 1, &window, 1, vDSP_Length(n))
        
        // Prepare FFT: create a DSPSplitComplex to hold the FFT output
        var realp = [Float](repeating: 0.0, count: n/2)
        var imagp = [Float](repeating: 0.0, count: n/2)
        var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
        
        // Convert the real array into split complex format
        window.withUnsafeBufferPointer { pointer in
            pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n) { typeConvertedTransferBuffer in
                vDSP_ctoz(typeConvertedTransferBuffer, 2, &splitComplex, 1, vDSP_Length(n/2))
            }
        }
        
        // Perform FFT
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Compute magnitudes from the FFT output
        var magnitudes = [Float](repeating: 0.0, count: n/2)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))
        
        // Normalize the magnitude spectrum
        var normalizedMagnitudes = [Float](repeating: 0.0, count: n/2)
        var scale: Float = 1.0 / Float(n)
        vDSP_vsmul(magnitudes, 1, &scale, &normalizedMagnitudes, 1, vDSP_Length(n/2))
        
        vDSP_destroy_fftsetup(fftSetup)
        
        return normalizedMagnitudes
    }
    
    private func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        guard vectorA.count == vectorB.count else { return 0 }
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        for i in 0..<vectorA.count {
            dotProduct += vectorA[i] * vectorB[i]
            normA += vectorA[i] * vectorA[i]
            normB += vectorB[i] * vectorB[i]
        }
        return dotProduct / (sqrt(normA) * sqrt(normB) + 1e-10)
    }
    
    private func compareFeatures(_ features: [Float]) -> Float {
        var maxSimilarity: Float = 0.0
        for calib in calibrationSamples {
            let similarity = cosineSimilarity(features, calib)
            if similarity > maxSimilarity {
                maxSimilarity = similarity
            }
        }
        return maxSimilarity
    }
}
