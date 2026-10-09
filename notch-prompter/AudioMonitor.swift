//
//  AudioMonitor.swift
//  notch-prompter
//
//  Created by Jakub Pomykała on 07/12/2025.
//


import AVFoundation
import SwiftUI
import Combine
import Accelerate

class AudioMonitor: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode?
    private var timer: Timer?
    private let smoothingFactor: Float = 0.5
    private var lastPublishTime = Date.timeIntervalSinceReferenceDate
    private var smoothedRms: Float = 0 // only touched on the audio thread
    private var isMonitoring = false

    @Published var rmsLevel: Float = 0


    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }

    func startMonitoring() {
        // Installing a second tap on the same bus throws an exception
        guard !isMonitoring, let inputNode = inputNode else { return }
        let format = inputNode.outputFormat(forBus: 0)

        // No input device (e.g. Mac without a mic) gives an empty format, and installTap throws on it
        guard format.channelCount > 0, format.sampleRate > 0 else {
            print("No audio input device available")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, time in
            guard let self = self else { return }

            let rms = self.rms(buffer: buffer)
            self.smoothedRms = (self.smoothedRms * (1 - self.smoothingFactor)) + (rms * self.smoothingFactor)
            let level = self.smoothedRms
            DispatchQueue.main.async {
                self.rmsLevel = level
            }
        }

        do {
            try audioEngine.start()
            isMonitoring = true
        } catch {
            inputNode.removeTap(onBus: 0)
            print("Error starting audio engine: \(error)")
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()
        isMonitoring = false
        rmsLevel = 0
    }

    private func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = vDSP_Length(buffer.frameLength)

        var rmsValue: Float = 0
        vDSP_rmsqv(channelData, 1, &rmsValue, frameLength)

        return rmsValue
    }
}
