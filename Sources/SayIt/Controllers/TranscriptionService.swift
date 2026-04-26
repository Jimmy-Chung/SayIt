import AVFoundation

/// 转写服务抽象协议，支持本地（whisper.cpp）或在线（ASR API）实现
protocol TranscriptionService: AnyObject {
    var isLoaded: Bool { get }

    /// 加载/初始化服务，完成后回调主线程
    func prepare(completion: @escaping (Bool) -> Void)

    /// 转写音频文件，completion 可能在任意线程回调
    func transcribe(audioURL: URL, language: String, completion: @escaping (String?) -> Void)

    /// 转写 PCM buffer（用于录音中实时转写），completion 可能在任意线程回调
    func transcribeBuffer(pcmData: Data, format: AVAudioFormat, language: String, completion: @escaping (String?) -> Void)
}
