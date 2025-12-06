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
    @Published var isPlaying: Bool = false
    @Published var offset: CGFloat = 0
    @Published var speed: Double = 12.0
    @Published var fontSize: Double = 14.0
    @Published var pauseOnHover: Bool = true
    
    
    private var timerCancellable: AnyCancellable?
    private var lastTick: CFTimeInterval?
    
    init() {
        startTimer()
    }
    
    func play() {
        isPlaying = true
    }
    
    func pause() {
        isPlaying = false
    }
    
    func reset() {
        isPlaying = false
        offset = 0
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
}
