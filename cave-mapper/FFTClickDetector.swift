//
//  FFTClickDetector.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 29.03.25.
//
import SwiftUI

class FFTClickDetector: ObservableObject {
    
    @Published var clickCount = 0
    @Published var isListening = false
    @Published var isCalibrating = false

    private var audioEngine = AVAudioEngine()
    private let fftSize = 1024
    private var fftSetup: FFTSetup?

    // Calibration-related
    private var calibrationBuffers: [[Float]] = []
    private let calibrationDuration: TimeInterval = 3.0
    private var calibrationStartTime: Date?
    
    // Detected from calibration
    private var calibratedThreshold: Float = 30.0
    private var frequencyRange: (startHz: Float, endHz: Float) = (4000, 8000)

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func startListening() {
        setupAudioEngine(mode: .detecting)
    }

    func startCalibration() {
        clickCount = 0
        calibrationBuffers = []
        calibrationStartTime = Date()
        isCalibrating = true
        setupAudioEngine(mode: .calibrating)
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        isCalibrating = false
    }

    private enum Mode {
        case calibrating
        case detecting
    }

    private func setupAudioEngine(mode: Mode) {
        stopListening()

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { buffer, _ in
            if mode == .calibrating {
                self.collectCalibration(buffer: buffer, format: format)
            } else {
                self.detectClick(buffer: buffer, format: format)
            }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isListening = (mode == .detecting)
                self.isCalibrating = (mode == .calibrating)
            }

            print("🎧 Audio engine started in \(mode == .detecting ? "detection" : "calibration") mode")
        } catch {
            print("❌ Audio engine start failed: \(error)")
        }
    }

    private func collectCalibration(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        let spectrum = computeSpectrum(buffer: buffer)

        calibrationBuffers.append(spectrum)

        if let start = calibrationStartTime, Date().timeIntervalSince(start) > calibrationDuration {
            finalizeCalibration(sampleRate: Float(format.sampleRate))
        }
    }

    private func finalizeCalibration(sampleRate: Float) {
        isCalibrating = false
        stopListening()

        guard !calibrationBuffers.isEmpty else { return }

        let averageSpectrum = averageSpectrums(buffers: calibrationBuffers)
        let (startHz, endHz) = detectDominantFrequencyRange(from: averageSpectrum, sampleRate: sampleRate)
        let peakValue = averageSpectrum[Int((startHz / sampleRate) * Float(fftSize))..<Int((endHz / sampleRate) * Float(fftSize))].max() ?? 30.0

        frequencyRange = (startHz, endHz)
        calibratedThreshold = peakValue * 1.1 // Add some margin

        print("✅ Calibration complete.")
        print("Dominant range: \(Int(startHz))Hz–\(Int(endHz))Hz")
        print("Calibrated threshold: \(calibratedThreshold)")

        startListening()
    }

    private func detectClick(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        let spectrum = computeSpectrum(buffer: buffer)
        let sampleRate = Float(format.sampleRate)

        let binSize = sampleRate / Float(fftSize)
        let startBin = Int(frequencyRange.startHz / binSize)
        let endBin = min(Int(frequencyRange.endHz / binSize), spectrum.count - 1)

        let relevantBins = spectrum[startBin..<endBin]
        let peak = relevantBins.max() ?? 0

        if peak > calibratedThreshold {
            DispatchQueue.main.async {
                self.clickCount += 1
                print("🔔 Click detected (peak: \(peak))")
            }
        }
    }

    private func computeSpectrum(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let fftSetup = fftSetup, let channelData = buffer.floatChannelData?[0] else { return [] }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        let halfSize = fftSize / 2

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var output = DSPSplitComplex(realp: &real, imagp: &imag)

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var windowedSignal = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(channelData, 1, window, 1, &windowedSignal, 1, vDSP_Length(fftSize))

        windowedSignal.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize) { convPtr in
                vDSP_ctoz(convPtr, 2, &output, 1, vDSP_Length(halfSize))
            }
        }

        vDSP_fft_zrip(fftSetup, &output, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(halfSize))

        var result = [Float](repeating: 0.0, count: halfSize)
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(sqrtArray(magnitudes), 1, &scale, &result, 1, vDSP_Length(halfSize))

        return result
    }

    private func averageSpectrums(buffers: [[Float]]) -> [Float] {
        let count = buffers.count
        guard count > 0 else { return [] }

        var sum = buffers[0]
        for i in 1..<count {
            vDSP_vadd(sum, 1, buffers[i], 1, &sum, 1, vDSP_Length(sum.count))
        }

        var avg = [Float](repeating: 0, count: sum.count)
        var scale = 1.0 / Float(count)
        vDSP_vsmul(sum, 1, &scale, &avg, 1, vDSP_Length(sum.count))

        return avg
    }

    private func detectDominantFrequencyRange(from spectrum: [Float], sampleRate: Float) -> (Float, Float) {
        let binSize = sampleRate / Float(fftSize)
        let maxIndex = spectrum.firstIndex(of: spectrum.max() ?? 0) ?? 0

        let start = max(0, maxIndex - 5)
        let end = min(spectrum.count - 1, maxIndex + 5)

        let startHz = Float(start) * binSize
        let endHz = Float(end) * binSize

        return (startHz, endHz)
    }

    private func sqrtArray(_ input: [Float]) -> [Float] {
        var result = [Float](repeating: 0.0, count: input.count)
        vvsqrtf(&result, input, [Int32(input.count)])
        return result
    }
}
