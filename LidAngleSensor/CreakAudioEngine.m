//
//  CreakAudioEngine.m
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import "CreakAudioEngine.h"

// 音频参数映射常量
static const double kDeadzone = 1.0;          // 度/秒 - 低于此值：视为静止
static const double kVelocityFull = 10.0;     // 度/秒 - 在此速度或以下时最大吱吱声音量
static const double kVelocityQuiet = 100.0;   // 度/秒 - 在此速度或以上时静音（快速移动）

// 音高变化常量  
static const double kMinRate = 0.80;          // 最小变速率（慢速移动时音调较低）
static const double kMaxRate = 1.10;          // 最大变速率（快速移动时音调较高）

// 平滑和时间常量
static const double kAngleSmoothingFactor = 0.05;     // 传感器噪声的重度平滑（5% 新值，95% 旧值）
static const double kVelocitySmoothingFactor = 0.3;   // 速度的中度平滑
static const double kMovementThreshold = 0.5;         // 记录为移动的最小角度变化（度）
static const double kGainRampTimeMs = 50.0;           // 增益斜坡时间常数（毫秒）
static const double kRateRampTimeMs = 80.0;           // 速率斜坡时间常数（毫秒）
static const double kMovementTimeoutMs = 50.0;        // 激进速度衰减前的时间（毫秒）
static const double kVelocityDecayFactor = 0.5;       // 未检测到移动时的衰减率
static const double kAdditionalDecayFactor = 0.8;     // 超时后的额外衰减

@interface CreakAudioEngine ()

// 音频引擎组件
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *creakPlayerNode;
@property (nonatomic, strong) AVAudioUnitVarispeed *varispeadUnit;
@property (nonatomic, strong) AVAudioMixerNode *mixerNode;

// 音频文件
@property (nonatomic, strong) AVAudioFile *creakLoopFile;

// 状态跟踪
@property (nonatomic, assign) double lastLidAngle;
@property (nonatomic, assign) double smoothedLidAngle;
@property (nonatomic, assign) double lastUpdateTime;
@property (nonatomic, assign) double smoothedVelocity;
@property (nonatomic, assign) double targetGain;
@property (nonatomic, assign) double targetRate;
@property (nonatomic, assign) double currentGain;
@property (nonatomic, assign) double currentRate;
@property (nonatomic, assign) BOOL isFirstUpdate;
@property (nonatomic, assign) NSTimeInterval lastMovementTime;

@end

@implementation CreakAudioEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _isFirstUpdate = YES;
        _lastUpdateTime = CACurrentMediaTime();
        _lastMovementTime = CACurrentMediaTime();
        _lastLidAngle = 0.0;
        _smoothedLidAngle = 0.0;
        _smoothedVelocity = 0.0;
        _targetGain = 0.0;
        _targetRate = 1.0;
        _currentGain = 0.0;
        _currentRate = 1.0;
        
        if (![self setupAudioEngine]) {
            NSLog(@"[CreakAudioEngine] Failed to setup audio engine");
            return nil;
        }
        
        if (![self loadAudioFiles]) {
            NSLog(@"[CreakAudioEngine] Failed to load audio files");
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
    
    // 创建音频节点
    self.creakPlayerNode = [[AVAudioPlayerNode alloc] init];
    self.varispeadUnit = [[AVAudioUnitVarispeed alloc] init];
    self.mixerNode = self.audioEngine.mainMixerNode;
    
    // 将节点附加到引擎
    [self.audioEngine attachNode:self.creakPlayerNode];
    [self.audioEngine attachNode:self.varispeadUnit];
    
    // 加载文件后将建立音频连接以使用其原生格式
    return YES;
}

- (BOOL)loadAudioFiles {
    NSBundle *bundle = [NSBundle mainBundle];
    
    // 加载吱吱声循环文件
    NSString *creakPath = [bundle pathForResource:@"CREAK_LOOP" ofType:@"wav"];
    if (!creakPath) {
        NSLog(@"[CreakAudioEngine] Could not find CREAK_LOOP.wav");
        return NO;
    }
    
    NSError *error;
    NSURL *creakURL = [NSURL fileURLWithPath:creakPath];
    self.creakLoopFile = [[AVAudioFile alloc] initForReading:creakURL error:&error];
    if (!self.creakLoopFile) {
        NSLog(@"[CreakAudioEngine] Failed to load CREAK_LOOP.wav: %@", error.localizedDescription);
        return NO;
    }
    
    // 使用文件的原生格式连接音频图
    AVAudioFormat *fileFormat = self.creakLoopFile.processingFormat;
    
    // 连接音频图：吱吱声播放器 -> 变速 -> 混音器
    [self.audioEngine connect:self.creakPlayerNode to:self.varispeadUnit format:fileFormat];
    [self.audioEngine connect:self.varispeadUnit to:self.mixerNode format:fileFormat];
    return YES;
}

#pragma mark - Engine Control

- (void)startEngine {
    if (self.isEngineRunning) {
        return;
    }
    
    NSError *error;
    if (![self.audioEngine startAndReturnError:&error]) {
        NSLog(@"[CreakAudioEngine] Failed to start audio engine: %@", error.localizedDescription);
        return;
    }
    
    // 开始循环播放吱吱声
    [self startCreakLoop];
}

- (void)stopEngine {
    if (!self.isEngineRunning) {
        return;
    }
    
    [self.creakPlayerNode stop];
    [self.audioEngine stop];
}

- (BOOL)isEngineRunning {
    return self.audioEngine.isRunning;
}

#pragma mark - Creak Loop Management

- (void)startCreakLoop {
    if (!self.creakPlayerNode || !self.creakLoopFile) {
        return;
    }
    
    // 重置文件位置到开头
    self.creakLoopFile.framePosition = 0;
    
    // 安排吱吱声循环连续播放
    AVAudioFrameCount frameCount = (AVAudioFrameCount)self.creakLoopFile.length;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.creakLoopFile.processingFormat
                                                             frameCapacity:frameCount];
    
    NSError *error;
    if (![self.creakLoopFile readIntoBuffer:buffer error:&error]) {
        NSLog(@"[CreakAudioEngine] Failed to read creak loop into buffer: %@", error.localizedDescription);
        return;
    }
    
    [self.creakPlayerNode scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    [self.creakPlayerNode play];
    
    // 将初始音量设置为 0（将由增益控制）
    self.creakPlayerNode.volume = 0.0;
}

#pragma mark - Velocity Calculation and Parameter Mapping

- (void)updateWithLidAngle:(double)lidAngle {
    double currentTime = CACurrentMediaTime();
    
    if (self.isFirstUpdate) {
        self.lastLidAngle = lidAngle;
        self.smoothedLidAngle = lidAngle;
        self.lastUpdateTime = currentTime;
        self.lastMovementTime = currentTime;
        self.isFirstUpdate = NO;
        return;
    }
    
    // 计算时间增量
    double deltaTime = currentTime - self.lastUpdateTime;
    if (deltaTime <= 0 || deltaTime > 1.0) {
        // 如果时间增量无效或太大则跳过（可能应用已后台运行）
        self.lastUpdateTime = currentTime;
        return;
    }
    
    // 阶段 1：平滑原始角度输入以消除传感器抖动
    self.smoothedLidAngle = (kAngleSmoothingFactor * lidAngle) + 
                           ((1.0 - kAngleSmoothingFactor) * self.smoothedLidAngle);
    
    // 阶段 2：从平滑的角度数据计算速度
    double deltaAngle = self.smoothedLidAngle - self.lastLidAngle;
    double instantVelocity;
    
    // 应用移动阈值以消除剩余噪声
    if (fabs(deltaAngle) < kMovementThreshold) {
        instantVelocity = 0.0;
    } else {
        instantVelocity = fabs(deltaAngle / deltaTime);
        self.lastLidAngle = self.smoothedLidAngle;
    }
    
    // 阶段 3：应用速度平滑和衰减
    if (instantVelocity > 0.0) {
        // 检测到真实移动 - 应用中度平滑
        self.smoothedVelocity = (kVelocitySmoothingFactor * instantVelocity) + 
                               ((1.0 - kVelocitySmoothingFactor) * self.smoothedVelocity);
        self.lastMovementTime = currentTime;
    } else {
        // 未检测到移动 - 应用快速衰减
        self.smoothedVelocity *= kVelocityDecayFactor;
    }
    
    // 如果长时间没有移动则额外衰减
    double timeSinceMovement = currentTime - self.lastMovementTime;
    if (timeSinceMovement > (kMovementTimeoutMs / 1000.0)) {
        self.smoothedVelocity *= kAdditionalDecayFactor;
    }
    
    // 更新状态以进行下一次迭代
    self.lastUpdateTime = currentTime;
    
    // 应用基于速度的参数映射
    [self updateAudioParametersWithVelocity:self.smoothedVelocity];
}

- (void)setAngularVelocity:(double)velocity {
    self.smoothedVelocity = velocity;
    [self updateAudioParametersWithVelocity:velocity];
}

- (void)updateAudioParametersWithVelocity:(double)velocity {
    double speed = velocity; // 速度已经是绝对值
    
    // 计算目标增益：慢速移动 = 大声吱吱声，快速移动 = 安静/静音
    double gain;
    if (speed < kDeadzone) {
        gain = 0.0; // 低于死区：无声音
    } else {
        // 使用反转的平滑步进曲线以获得自然的音量响应
        double e0 = fmax(0.0, kVelocityFull - 0.5);
        double e1 = kVelocityQuiet + 0.5;
        double t = fmin(1.0, fmax(0.0, (speed - e0) / (e1 - e0)));
        double s = t * t * (3.0 - 2.0 * t); // 平滑步进函数
        gain = 1.0 - s; // 反转：慢速 = 响亮，快速 = 安静
        gain = fmax(0.0, fmin(1.0, gain));
    }
    
    // 根据移动速度计算目标音高/速度率
    double normalizedVelocity = fmax(0.0, fmin(1.0, speed / kVelocityQuiet));
    double rate = kMinRate + normalizedVelocity * (kMaxRate - kMinRate);
    rate = fmax(kMinRate, fmin(kMaxRate, rate));
    
    // 存储目标以实现平滑斜坡
    self.targetGain = gain;
    self.targetRate = rate;
    
    // 应用平滑的参数过渡
    [self rampToTargetParameters];
}

// 参数斜坡的辅助函数
- (double)rampValue:(double)current toward:(double)target withDeltaTime:(double)dt timeConstantMs:(double)tauMs {
    double alpha = fmin(1.0, dt / (tauMs / 1000.0)); // 线性斜坡系数
    return current + (target - current) * alpha;
}

- (void)rampToTargetParameters {
    if (!self.isEngineRunning) {
        return;
    }
    
    // 计算斜坡的增量时间
    static double lastRampTime = 0;
    double currentTime = CACurrentMediaTime();
    if (lastRampTime == 0) lastRampTime = currentTime;
    double deltaTime = currentTime - lastRampTime;
    lastRampTime = currentTime;
    
    // 将当前值向目标斜坡过渡以实现平滑转换
    self.currentGain = [self rampValue:self.currentGain toward:self.targetGain withDeltaTime:deltaTime timeConstantMs:kGainRampTimeMs];
    self.currentRate = [self rampValue:self.currentRate toward:self.targetRate withDeltaTime:deltaTime timeConstantMs:kRateRampTimeMs];
    
    // 将斜坡值应用于音频节点（2倍乘数以获得可听音量）
    self.creakPlayerNode.volume = (float)(self.currentGain * 2.0);
    self.varispeadUnit.rate = (float)self.currentRate;
}

#pragma mark - Property Accessors

- (double)currentVelocity {
    return self.smoothedVelocity;
}

- (double)currentGain {
    return _currentGain;
}

- (double)currentRate {
    return _currentRate;
}

@end

