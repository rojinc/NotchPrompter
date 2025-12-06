import Foundation
import Combine
import CoreVideo
import AVFoundation
import Accelerate

final class PrompterViewModel: ObservableObject {
    // User settings
    @Published var text: String = """
    This is a sample text for your prompter
    You can add your own text in Settings
    
    Here is a sample text:
    Et aliquip et aute duis. Et aute duis voluptate. Duis voluptate eiusmod elit amet excepteur non. Eiusmod elit amet excepteur, non. Excepteur non ex veniam aliquip enim irure. Ex veniam, aliquip enim irure nulla aliquip.

    Aliquip et aute duis, voluptate eiusmod elit amet. Duis voluptate eiusmod elit amet excepteur non. Eiusmod elit amet excepteur, non. Excepteur non ex veniam aliquip enim irure. Ex veniam, aliquip enim irure nulla aliquip. Enim irure nulla aliquip est et irure, elit. Aliquip est et, irure. Irure elit lorem proident, excepteur. Proident excepteur et ad nulla nulla cillum et. Et, ad nulla nulla.

    Et aute duis voluptate. Duis voluptate eiusmod elit amet excepteur non. Eiusmod elit amet excepteur, non. Excepteur non ex veniam aliquip enim irure. Ex veniam, aliquip enim irure nulla aliquip.

    Aute duis voluptate, eiusmod elit amet excepteur. Eiusmod elit amet excepteur, non. Excepteur non ex veniam aliquip enim irure. Ex veniam, aliquip enim irure nulla aliquip. Enim irure nulla aliquip est et irure, elit. Aliquip est et, irure. Irure elit lorem proident, excepteur. Proident excepteur et ad nulla nulla cillum et.
    """
    @Published var speed: Double = 12.0 // points per second
    @Published var fontSize: Double = 14.0

    @Published var pauseOnHover: Bool = false
    @Published var playOnAudio: Bool = false {
        didSet {
            handlePlayOnAudioChanged()
        }
    }

    @Published var isPlaying: Bool = false
    @Published var offset: CGFloat = 0

    private var timerCancellable: AnyCancellable?
    private var lastTick: CFTimeInterval?

    // Audio
    private let audioMonitor = AudioMonitor()
    private var audioCancellables: Set<AnyCancellable> = []

    init() {
        startTimer()
        bindAudioLevel()
    }

    func togglePlayPause() {
        isPlaying.toggle()
    }

    private func startTimer() {
        // Use a high-frequency timer for smoothness (display refresh)
        timerCancellable = CADisplayLinkPublisher()
            .receive(on: RunLoop.main)
            .sink { [weak self] timestamp in
                self?.tick(current: timestamp)
            }
    }

    private func tick(current: CFTimeInterval) {
        guard isPlaying else {
            lastTick = current
            return
        }
        let dt: CFTimeInterval
        if let last = lastTick {
            dt = current - last
        } else {
            dt = 0
        }
        lastTick = current

        // Advance offset by speed (points/sec) * dt
        let delta = CGFloat(speed) * CGFloat(dt)
        offset += delta
    }

    // MARK: - Audio-driven play/pause

    private func bindAudioLevel() {
        // Configure thresholds
        let startThresholdDB: Float = -35.0   // louder than this triggers play
        let stopThresholdDB: Float  = -50.0   // quieter than this counts as silence
        let silenceTimeout: TimeInterval = 0.8

        var lastAboveThresholdDate: Date?
        var lastBelowThresholdDate: Date?

        audioMonitor.levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] db in
                guard let self else { return }
                guard self.playOnAudio else { return }

                let now = Date()

                if db > startThresholdDB {
                    lastAboveThresholdDate = now
                    // If we detect voice, start playing
                    if !self.isPlaying {
                        self.isPlaying = true
                    }
                } else if db < stopThresholdDB {
                    lastBelowThresholdDate = now
                }

                // If we've been below the stop threshold for long enough, pause
                if let lastLow = lastBelowThresholdDate,
                   now.timeIntervalSince(lastLow) > silenceTimeout {
                    if self.isPlaying {
                        self.isPlaying = false
                    }
                }
            }
            .store(in: &audioCancellables)
    }

    private func handlePlayOnAudioChanged() {
        if playOnAudio {
            audioMonitor.start()
        } else {
            audioMonitor.stop()
        }
    }
}

// MARK: - Audio Monitor

private final class AudioMonitor {
    private let engine = AVAudioEngine()
    #if !os(macOS)
    private let session = AVAudioSession.sharedInstance()
    #endif
    private(set) var isRunning: Bool = false

    // Publishes smoothed dBFS levels (negative values; 0 is max)
    let levelPublisher = PassthroughSubject<Float, Never>()

    // RMS smoothing
    private var ema: Float = -80.0
    private let alpha: Float = 0.2 // exponential moving average factor

    func start() {
        guard !isRunning else { return }

        // Configure session where available (not on macOS)
        #if !os(macOS)
        Task { @MainActor in
            do {
                try session.setCategory(.record, options: [])
                try session.setActive(true)
            } catch {
                // Session configuration failed; we can still attempt engine start
            }
            self.setupAndStartEngine()
        }
        #else
        // On macOS, no AVAudioSession; just start the engine
        setupAndStartEngine()
        #endif
    }

    private func setupAndStartEngine() {
        engine.inputNode.removeTap(onBus: 0)

        let format = engine.inputNode.inputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let db = Self.computeDBFS(buffer: buffer)
            // Smooth with EMA to avoid flicker
            self.ema = self.alpha * db + (1 - self.alpha) * self.ema
            self.levelPublisher.send(self.ema)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            // Could not start engine; stop any partial setup
            stop()
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    deinit {
        stop()
    }

    private static func computeDBFS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?.pointee else {
            return -80.0
        }
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return -80.0 }

        var rms: Float = 0.0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameLength))
        rms = sqrtf(rms)
        let minRms: Float = 1e-7
        let level = max(rms, minRms)
        let db = 20 * log10f(level)
        return db.isFinite ? db : -80.0
    }
}

// MARK: - Display link publisher

// A Combine publisher backed by CVDisplayLink for smooth ticks.
private final class CADisplayLinkProxy {
    let subject = PassthroughSubject<CFTimeInterval, Never>()
    var link: CVDisplayLink?

    init() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        self.link = link
        if let l = link {
            CVDisplayLinkSetOutputCallback(l, { (_, _, _, _, _, userInfo) -> CVReturn in
                let ref = Unmanaged<CADisplayLinkProxy>.fromOpaque(userInfo!).takeUnretainedValue()
                let ts = CFAbsoluteTimeGetCurrent()
                ref.subject.send(ts)
                return kCVReturnSuccess
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            CVDisplayLinkStart(l)
        }
    }

    deinit {
        if let l = link {
            CVDisplayLinkStop(l)
        }
    }
}

private struct CADisplayLinkPublisher: Publisher {
    typealias Output = CFTimeInterval
    typealias Failure = Never

    func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, CFTimeInterval == S.Input {
        let proxy = CADisplayLinkProxy()
        subscriber.receive(subscription: SubscriptionImpl(subscriber: subscriber, proxy: proxy))
    }

    private final class SubscriptionImpl<S: Subscriber>: Subscription where S.Input == CFTimeInterval, S.Failure == Never {
        private var subscriber: S?
        private var proxy: CADisplayLinkProxy?
        private var cancellables: Set<AnyCancellable> = []

        init(subscriber: S, proxy: CADisplayLinkProxy) {
            self.subscriber = subscriber
            self.proxy = proxy

            proxy.subject
                .sink { [weak self] value in
                    _ = self?.subscriber?.receive(value)
                }
                .store(in: &cancellables)
        }

        func request(_ demand: Subscribers.Demand) {
            // We push at display refresh rate; demand not used.
        }

        func cancel() {
            subscriber = nil
            proxy = nil
            cancellables.removeAll()
        }
    }
}
