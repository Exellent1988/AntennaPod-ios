import AVFoundation
import AudioDSP
import MediaToolbox

/// Shared playback audio pipeline: one `MTAudioProcessingTap` per audio track of the current
/// `AVPlayerItem`, all feeding the same `AudioProcessingChain` (pure Swift in the `AudioDSP` package).
///
/// Why a tap and not a standalone `AVAudioEngine` graph: the tap runs inside AVPlayer's own render
/// path, so streaming, video surface / PiP, AirPlay, Now Playing, `rate`, and
/// `audioTimePitchAlgorithm` keep working unchanged. Limits: Apple does not run taps for HLS /
/// FairPlay items — features built on the pipeline then simply have no effect for that item.
final class PlayerAudioPipeline {
    let chain = AudioProcessingChain()
    /// Global soft gain stage (Settings Volume boost and per-feed Volume adaptation multiply here).
    let gain = GainStage()

    init() {
        chain.append(gain)
    }

    /// Builds an `AVAudioMix` whose input parameters carry a tap feeding `chain`.
    /// Returns `nil` when the tap cannot be created (caller then leaves `audioMix` unset).
    func makeAudioMix(for tracks: [AVAssetTrack]) -> AVAudioMix? {
        var params: [AVAudioMixInputParameters] = []
        for track in tracks {
            guard let tap = Self.makeTap(chain: chain) else { return nil }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.audioTapProcessor = tap
            params.append(p)
        }
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }

    // MARK: - MTAudioProcessingTap glue

    /// Per-tap context. Retained by the tap via `clientInfo`, released in `finalize`.
    private final class TapContext {
        let chain: AudioProcessingChain
        var sampleRate: Double = 44_100
        var isFloat32NonInterleaved = false
        init(chain: AudioProcessingChain) { self.chain = chain }
    }

    private static func makeTap(chain: AudioProcessingChain) -> MTAudioProcessingTap? {
        let context = TapContext(chain: chain)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<TapContext>.fromOpaque(storage).release()
            },
            prepare: { tap, _, format in
                let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let asbd = format.pointee
                ctx.sampleRate = asbd.mSampleRate
                ctx.isFloat32NonInterleaved =
                    asbd.mFormatID == kAudioFormatLinearPCM
                    && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                    && (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
                    && asbd.mBitsPerChannel == 32
                ctx.chain.reset()
            },
            unprepare: nil,
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
                )
                guard status == noErr else { return }
                let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                // AVPlayer hands taps canonical Float32 non-interleaved PCM; anything else passes through.
                guard ctx.isFloat32NonInterleaved else { return }
                let frames = Int(numberFramesOut.pointee)
                let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
                var channels: [UnsafeMutableBufferPointer<Float>] = []
                channels.reserveCapacity(abl.count)
                for buffer in abl {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    channels.append(UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
                }
                var block = AudioBlock(channels: channels, frameCount: frames, sampleRate: ctx.sampleRate)
                ctx.chain.process(&block)
            }
        )
        // Current SDK overlay: the out-parameter is a managed `MTAudioProcessingTap?` (no Unmanaged).
        var tapOut: MTAudioProcessingTap?
        let err = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut
        )
        guard err == noErr, let tap = tapOut else {
            Unmanaged<TapContext>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        return tap
    }
}
