import AudioToolbox
import AVFoundation
import Foundation
import IIGSCore

final class DiskTestAudioPlayer: @unchecked Sendable {
    private let sampleRate = IIGSSoundController.defaultSampleRate
    private let channelCount = IIGSSoundController.channelCount
    private let sampleQueue = DiskTestAudioSampleQueue(
        capacityFrames: IIGSSoundController.defaultSampleRate
    )

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var volume: Float = 1.0
    private var muted = false

    func start() throws {
        if engine == nil {
            try configureEngine()
        }

        guard let engine else {
            return
        }

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }

        updateOutputVolume()
    }

    func stop() {
        engine?.stop()
        clear()
    }

    func clear() {
        sampleQueue.clear()
    }

    func enqueue(_ buffer: IIGSAudioBuffer) {
        guard buffer.sampleRate == sampleRate,
              buffer.channelCount == channelCount
        else {
            return
        }

        sampleQueue.append(buffer.samples)
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        updateOutputVolume()
    }

    func setVolume(_ volume: Double) {
        self.volume = Float(min(max(volume, 0), 1))
        updateOutputVolume()
    }

    private func configureEngine() throws {
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channelCount)
        ) else {
            throw DiskTestAudioError.invalidFormat
        }

        let sourceNode = AVAudioSourceNode(format: format) { [sampleQueue] _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            sampleQueue.render(to: buffers, frameCount: Int(frameCount))
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        self.engine = engine
        self.sourceNode = sourceNode
    }

    private func updateOutputVolume() {
        engine?.mainMixerNode.outputVolume = muted ? 0 : volume
    }
}

private enum DiskTestAudioError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not create a 48 kHz stereo audio format"
        }
    }
}

private final class DiskTestAudioSampleQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16]
    private var readIndex = 0
    private var writeIndex = 0
    private var availableSamples = 0

    init(capacityFrames: Int) {
        samples = Array(repeating: 0, count: max(1, capacityFrames) * IIGSSoundController.channelCount)
    }

    func append(_ incomingSamples: [Int16]) {
        let usableCount = incomingSamples.count - (incomingSamples.count % IIGSSoundController.channelCount)
        guard usableCount > 0 else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let startIndex = max(0, usableCount - samples.count)
        for sample in incomingSamples[startIndex..<usableCount] {
            if availableSamples == samples.count {
                readIndex = (readIndex + 1) % samples.count
                availableSamples -= 1
            }

            samples[writeIndex] = sample
            writeIndex = (writeIndex + 1) % samples.count
            availableSamples += 1
        }
    }

    func clear() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        availableSamples = 0
        lock.unlock()
    }

    func render(to buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard frameCount > 0 else {
            return
        }

        guard lock.try() else {
            fillSilence(buffers: buffers, frameCount: frameCount)
            return
        }

        defer { lock.unlock() }

        if buffers.count == 1, buffers[0].mNumberChannels >= 2 {
            renderInterleaved(to: buffers, frameCount: frameCount)
        } else {
            renderNonInterleaved(to: buffers, frameCount: frameCount)
        }
    }

    private func renderNonInterleaved(to buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
        else {
            fillSilence(buffers: buffers, frameCount: frameCount)
            return
        }

        buffers[0].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.stride)
        buffers[1].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.stride)

        for frame in 0..<frameCount {
            let pair = popStereoSample()
            left[frame] = pair.left
            right[frame] = pair.right
        }
    }

    private func renderInterleaved(to buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard let output = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
            return
        }

        buffers[0].mDataByteSize = UInt32(frameCount * IIGSSoundController.channelCount * MemoryLayout<Float>.stride)

        for frame in 0..<frameCount {
            let pair = popStereoSample()
            let baseIndex = frame * IIGSSoundController.channelCount
            output[baseIndex] = pair.left
            output[baseIndex + 1] = pair.right
        }
    }

    private func popStereoSample() -> (left: Float, right: Float) {
        guard availableSamples >= IIGSSoundController.channelCount else {
            return (0, 0)
        }

        let left = samples[readIndex]
        readIndex = (readIndex + 1) % samples.count
        let right = samples[readIndex]
        readIndex = (readIndex + 1) % samples.count
        availableSamples -= IIGSSoundController.channelCount

        return (Float(left) / 32_768.0, Float(right) / 32_768.0)
    }

    private func fillSilence(buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        for index in 0..<buffers.count {
            guard let output = buffers[index].mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }

            let channelCount = max(1, Int(buffers[index].mNumberChannels))
            let sampleCount = frameCount * channelCount
            buffers[index].mDataByteSize = UInt32(sampleCount * MemoryLayout<Float>.stride)
            output.initialize(repeating: 0, count: sampleCount)
        }
    }
}
