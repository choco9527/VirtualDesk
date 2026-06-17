import Foundation

final class StopController {
    private let lock = NSLock()
    private var stopped = false

    func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func shouldStop() -> Bool {
        lock.lock()
        let value = stopped
        lock.unlock()

        return value
    }
}

final class TerminationSignalHandler {
    private var sources: [DispatchSourceSignal] = []

    init(onSignal: @escaping () -> Void) {
        [SIGINT, SIGTERM].forEach { signalValue in
            signal(signalValue, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalValue, queue: .global())
            source.setEventHandler(handler: onSignal)
            source.resume()
            sources.append(source)
        }
    }
}
