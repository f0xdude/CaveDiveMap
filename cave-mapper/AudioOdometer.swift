import SwiftUI
import AVFoundation

struct AudioOdometer: View {
    @StateObject private var clickDetector = ClickDetector()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Click Count: \(clickDetector.clickCount)")
                .font(.largeTitle)
            
            if clickDetector.isRecording {
                Text("Listening...")
                    .foregroundColor(.green)
            } else {
                Button("Start Listening") {
                    clickDetector.start()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            
            if clickDetector.isRecording {
                Button("Stop Listening") {
                    clickDetector.stop()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            clickDetector.requestPermission()
        }
    }
}

class ClickDetector: ObservableObject {
    @Published var clickCount = 0
    @Published var isRecording = false
    
    private let audioEngine = AVAudioEngine()
    private var lastClickTime: TimeInterval = 0
    // Adjust the threshold based on your environment
    private let threshold: Float = 0.07
    // Cooldown period to prevent multiple counts per click
    private let clickCooldown: TimeInterval = 0.2
    
    /// Request microphone permission using the new API on iOS 17+ and fallback on earlier versions.
    func requestPermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: { granted in
                if !granted {
                    print("Microphone permission not granted")
                }
            })
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    print("Microphone permission not granted")
                }
            }
        }
    }
    
    /// Start the audio engine and install a tap to process microphone input.
    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
        } catch {
            print("Audio session setup failed:", error)
        }
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer)
        }
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Audio Engine couldn't start:", error)
        }
    }
    
    /// Stop the audio engine and remove the tap.
    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    /// Process the audio buffer to compute RMS and count clicks when the amplitude exceeds a threshold.
    func processAudio(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        
        // Compute the RMS amplitude
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        let currentTime = Date().timeIntervalSince1970
        // Count a click if RMS exceeds the threshold and cooldown has passed.
        if rms > threshold, currentTime - lastClickTime > clickCooldown {
            lastClickTime = currentTime
            DispatchQueue.main.async {
                self.clickCount += 1
            }
        }
    }
}

