//
//  ThereminAudioEngine.m
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import "ThereminAudioEngine.h"
#import <AudioToolbox/AudioToolbox.h>

// 特雷门琴参数映射常量
static const double kMinFrequency = 110.0;       // Hz - A2 音符（屏幕关闭）
static const double kMaxFrequency = 880.0;       // Hz - A5 音符（屏幕完全打开）
static const double kMinAngle = 0.0;             // 度 - 屏幕关闭
static const double kMaxAngle = 135.0;           // 度 - 屏幕完全打开

// 音量控制常量 - 具有速度调制的连续音调
static const double kBaseVolume = 0.6;           // 静止时的基础音量
static const double kVelocityVolumeBoost = 0.4;  // 来自移动的额外音量提升
static const double kVelocityFull = 8.0;         // 度/秒 - 在此速度或以下时最大音量提升
static const double kVelocityQuiet = 80.0;       // 度/秒 - 超过此速度时无音量提升

// 颤音常量
static const double kVibratoFrequency = 5.0;     // Hz - 颤音速率
static const double kVibratoDepth = 0.03;        // 颤音深度作为频率的分数（3%）

// 平滑常量
static const double kAngleSmoothingFactor = 0.1;      // 频率的中度平滑
static const double kVelocitySmoothingFactor = 0.3;   // 速度的中度平滑
static const double kFrequencyRampTimeMs = 30.0;      // 频率斜坡时间常数
static const double kVolumeRampTimeMs = 50.0;         // 音量斜坡时间常数
static const double kMovementThreshold = 0.3;         // 记录移动的最小角度变化
static const double kMovementTimeoutMs = 100.0;       // 速度衰减前的时间
static const double kVelocityDecayFactor = 0.7;       // 无移动时的衰减率
static const double kAdditionalDecayFactor = 0.85;    // 超时后的额外衰减

// Audio constants
static const double kSampleRate = 44100.0;
static const UInt32 kBufferSize = 512;

@interface ThereminAudioEngine ()

// Audio engine components
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioSourceNode *sourceNode;
@property (nonatomic, strong) AVAudioMixerNode *mixerNode;

// State tracking
@property (nonatomic, assign) double lastLidAngle;
@property (nonatomic, assign) double smoothedLidAngle;
@property (nonatomic, assign) double lastUpdateTime;
@property (nonatomic, assign) double smoothedVelocity;
@property (nonatomic, assign) double targetFrequency;
@property (nonatomic, assign) double targetVolume;
@property (nonatomic, assign) double currentFrequency;
@property (nonatomic, assign) double currentVolume;
@property (nonatomic, assign) BOOL isFirstUpdate;
@property (nonatomic, assign) NSTimeInterval lastMovementTime;

// 正弦波生成
@property (nonatomic, assign) double phase;
@property (nonatomic, assign) double phaseIncrement;

// 颤音生成
@property (nonatomic, assign) double vibratoPhase;

@end

@implementation ThereminAudioEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _isFirstUpdate = YES;
        _lastUpdateTime = CACurrentMediaTime();
        _lastMovementTime = CACurrentMediaTime();
        _lastLidAngle = 0.0;
        _smoothedLidAngle = 0.0;
        _smoothedVelocity = 0.0;
        _targetFrequency = kMinFrequency;
        _targetVolume = kBaseVolume;
        _currentFrequency = kMinFrequency;
        _currentVolume = kBaseVolume;
        _phase = 0.0;
        _vibratoPhase = 0.0;
        _phaseIncrement = 2.0 * M_PI * kMinFrequency / kSampleRate;
        
        if (![self setupAudioEngine]) {
            NSLog(@"[ThereminAudioEngine] Failed to setup audio engine");
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [self stopEngine];
}

#pragma mark - Audio Engine Setup

- (BOOL)setupAudioEngine {
    self.audioEngine = [[AVAudioEngine alloc] init];
    self.mixerNode = self.audioEngine.mainMixerNode;
    
    // 为我们的正弦波创建音频格式
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:kSampleRate
                                                               channels:1
                                                            interleaved:NO];
    
    // 创建正弦波生成的源节点
    __weak typeof(self) weakSelf = self;
    self.sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL * _Nonnull isSilence, const AudioTimeStamp * _Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList * _Nonnull outputData) {
        return [weakSelf renderSineWave:isSilence timestamp:timestamp frameCount:frameCount outputData:outputData];
    }];
    
    // 附加并连接源节点
    [self.audioEngine attachNode:self.sourceNode];
    [self.audioEngine connect:self.sourceNode to:self.mixerNode format:format];
    
    return YES;
}

#pragma mark - Engine Control

- (void)startEngine {
    if (self.isEngineRunning) {
        return;
    }
    
    NSError *error;
    if (![self.audioEngine startAndReturnError:&error]) {
        NSLog(@"[ThereminAudioEngine] Failed to start audio engine: %@", error.localizedDescription);
        return;
    }
    
    NSLog(@"[ThereminAudioEngine] Started theremin engine");
}

- (void)stopEngine {
    if (!self.isEngineRunning) {
        return;
    }
    
    [self.audioEngine stop];
    NSLog(@"[ThereminAudioEngine] Stopped theremin engine");
}

- (BOOL)isEngineRunning {
    return self.audioEngine.isRunning;
}

#pragma mark - Sine Wave Generation

- (OSStatus)renderSineWave:(BOOL *)isSilence
                 timestamp:(const AudioTimeStamp *)timestamp
                frameCount:(AVAudioFrameCount)frameCount
                outputData:(AudioBufferList *)outputData {
    
    float *output = (float *)outputData->mBuffers[0].mData;
    
    // 始终生成声音（连续音调）
    *isSilence = NO;
    
    // 计算颤音相位增量
    double vibratoPhaseIncrement = 2.0 * M_PI * kVibratoFrequency / kSampleRate;
    
    // 生成带颤音的正弦波样本
    for (AVAudioFrameCount i = 0; i < frameCount; i++) {
        // 计算颤音调制
        double vibratoModulation = sin(self.vibratoPhase) * kVibratoDepth;
        double modulatedFrequency = self.currentFrequency * (1.0 + vibratoModulation);
        
        // 更新调制频率的相位增量
        self.phaseIncrement = 2.0 * M_PI * modulatedFrequency / kSampleRate;
        
        // 生成带颤音和当前音量的样本
        output[i] = (float)(sin(self.phase) * self.currentVolume * 0.25); // 0.25 以防止削波
        
        // 更新相位
        self.phase += self.phaseIncrement;
        self.vibratoPhase += vibratoPhaseIncrement;
        
        // 包装相位以防止浮点误差累积
        if (self.phase >= 2.0 * M_PI) {
            self.phase -= 2.0 * M_PI;
        }
        if (self.vibratoPhase >= 2.0 * M_PI) {
            self.vibratoPhase -= 2.0 * M_PI;
        }
    }
    
    return noErr;
}

#pragma mark - Lid Angle Processing

- (void)updateWithLidAngle:(double)lidAngle {
    double currentTime = CACurrentMediaTime();
    
    if (self.isFirstUpdate) {
        self.lastLidAngle = lidAngle;
        self.smoothedLidAngle = lidAngle;
        self.lastUpdateTime = currentTime;
        self.lastMovementTime = currentTime;
        self.isFirstUpdate = NO;
        
        // 根据角度设置初始频率
        [self updateTargetParametersWithAngle:lidAngle velocity:0.0];
        return;
    }
    
    // Calculate time delta
    double deltaTime = currentTime - self.lastUpdateTime;
    if (deltaTime <= 0 || deltaTime > 1.0) {
        // 如果时间增量无效或太大则跳过
        self.lastUpdateTime = currentTime;
        return;
    }
    
    // 阶段 1：平滑原始角度输入
    self.smoothedLidAngle = (kAngleSmoothingFactor * lidAngle) + 
                           ((1.0 - kAngleSmoothingFactor) * self.smoothedLidAngle);
    
    // 阶段 2：从平滑的角度数据计算速度
    double deltaAngle = self.smoothedLidAngle - self.lastLidAngle;
    double instantVelocity;
    
    // 应用移动阈值
    if (fabs(deltaAngle) < kMovementThreshold) {
        instantVelocity = 0.0;
    } else {
        instantVelocity = fabs(deltaAngle / deltaTime);
        self.lastLidAngle = self.smoothedLidAngle;
    }
    
    // Stage 3: Apply velocity smoothing and decay
    if (instantVelocity > 0.0) {
        self.smoothedVelocity = (kVelocitySmoothingFactor * instantVelocity) + 
                               ((1.0 - kVelocitySmoothingFactor) * self.smoothedVelocity);
        self.lastMovementTime = currentTime;
    } else {
        self.smoothedVelocity *= kVelocityDecayFactor;
    }
    
    // Additional decay if no movement for extended period
    double timeSinceMovement = currentTime - self.lastMovementTime;
    if (timeSinceMovement > (kMovementTimeoutMs / 1000.0)) {
        self.smoothedVelocity *= kAdditionalDecayFactor;
    }
    
    // Update state for next iteration
    self.lastUpdateTime = currentTime;
    
    // 更新目标参数
    [self updateTargetParametersWithAngle:self.smoothedLidAngle velocity:self.smoothedVelocity];
    
    // Apply smooth parameter transitions
    [self rampToTargetParameters];
}

- (void)setAngularVelocity:(double)velocity {
    self.smoothedVelocity = velocity;
    [self updateTargetParametersWithAngle:self.smoothedLidAngle velocity:velocity];
    [self rampToTargetParameters];
}

- (void)updateTargetParametersWithAngle:(double)angle velocity:(double)velocity {
    // 使用指数曲线将角度映射到频率以获得音乐感
    double normalizedAngle = fmax(0.0, fmin(1.0, (angle - kMinAngle) / (kMaxAngle - kMinAngle)));
    
    // 使用指数映射以获得更音乐化的频率分布
    double frequencyRatio = pow(normalizedAngle, 0.7); // 轻微压缩以获得更好的控制
    self.targetFrequency = kMinFrequency + frequencyRatio * (kMaxFrequency - kMinFrequency);
    
    // 计算具有基于速度提升的连续音量
    double velocityBoost = 0.0;
    if (velocity > 0.0) {
        // 使用平滑步进曲线以获得自然的音量提升响应
        double e0 = 0.0;
        double e1 = kVelocityQuiet;
        double t = fmin(1.0, fmax(0.0, (velocity - e0) / (e1 - e0)));
        double s = t * t * (3.0 - 2.0 * t); // 平滑步进函数
        velocityBoost = (1.0 - s) * kVelocityVolumeBoost; // 反转：慢速 = 更多提升，快速 = 更少提升
    }
    
    // 将基础音量与速度提升相结合
    self.targetVolume = kBaseVolume + velocityBoost;
    self.targetVolume = fmax(0.0, fmin(1.0, self.targetVolume));
}

// Helper function for parameter ramping
- (double)rampValue:(double)current toward:(double)target withDeltaTime:(double)dt timeConstantMs:(double)tauMs {
    double alpha = fmin(1.0, dt / (tauMs / 1000.0));
    return current + (target - current) * alpha;
}

- (void)rampToTargetParameters {
    // Calculate delta time for ramping
    static double lastRampTime = 0;
    double currentTime = CACurrentMediaTime();
    if (lastRampTime == 0) lastRampTime = currentTime;
    double deltaTime = currentTime - lastRampTime;
    lastRampTime = currentTime;
    
    // Ramp current values toward targets for smooth transitions
    self.currentFrequency = [self rampValue:self.currentFrequency toward:self.targetFrequency withDeltaTime:deltaTime timeConstantMs:kFrequencyRampTimeMs];
    self.currentVolume = [self rampValue:self.currentVolume toward:self.targetVolume withDeltaTime:deltaTime timeConstantMs:kVolumeRampTimeMs];
}

#pragma mark - Property Accessors

- (double)currentVelocity {
    return self.smoothedVelocity;
}

@end
