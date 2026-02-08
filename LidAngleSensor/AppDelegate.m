//
//  AppDelegate.m
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import "AppDelegate.h"
#import "LidAngleSensor.h"
#import "CreakAudioEngine.h"
#import "ThereminAudioEngine.h"
#import "NSLabel.h"

typedef NS_ENUM(NSInteger, AudioMode) {
    AudioModeCreak,
    AudioModeTheremin
};

@interface AppDelegate ()
@property (strong, nonatomic) LidAngleSensor *lidSensor;
@property (strong, nonatomic) CreakAudioEngine *creakAudioEngine;
@property (strong, nonatomic) ThereminAudioEngine *thereminAudioEngine;
@property (strong, nonatomic) NSLabel *angleLabel;
@property (strong, nonatomic) NSLabel *statusLabel;
@property (strong, nonatomic) NSLabel *velocityLabel;
@property (strong, nonatomic) NSLabel *audioStatusLabel;
@property (strong, nonatomic) NSButton *audioToggleButton;
@property (strong, nonatomic) NSSegmentedControl *modeSelector;
@property (strong, nonatomic) NSLabel *modeLabel;
@property (strong, nonatomic) NSTimer *updateTimer;
@property (nonatomic, assign) AudioMode currentAudioMode;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.currentAudioMode = AudioModeCreak; // 默认为吱吱声模式
    [self createWindow];
    [self initializeLidSensor];
    [self initializeAudioEngines];
    [self startUpdatingDisplay];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self.updateTimer invalidate];
    [self.lidSensor stopLidAngleUpdates];
    [self.creakAudioEngine stopEngine];
    [self.thereminAudioEngine stopEngine];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)createWindow {
    // 创建主窗口（更高以容纳模式选择和音频控制）
    NSRect windowFrame = NSMakeRect(100, 100, 450, 480);
    self.window = [[NSWindow alloc] initWithContentRect:windowFrame
                                              styleMask:NSWindowStyleMaskTitled | 
                                                       NSWindowStyleMaskClosable | 
                                                       NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    
    [self.window setTitle:@"MacBook 屏幕角度传感器"];
    [self.window makeKeyAndOrderFront:nil];
    [self.window center];
    
    // 创建内容视图
    NSView *contentView = [[NSView alloc] initWithFrame:windowFrame];
    [self.window setContentView:contentView];
    
    // 创建角度显示标签，使用表格数字（更大、轻字体）
    self.angleLabel = [[NSLabel alloc] init];
    [self.angleLabel setStringValue:@"初始化中..."];
    [self.angleLabel setFont:[NSFont monospacedDigitSystemFontOfSize:48 weight:NSFontWeightLight]];
    [self.angleLabel setAlignment:NSTextAlignmentCenter];
    [self.angleLabel setTextColor:[NSColor systemBlueColor]];
    [contentView addSubview:self.angleLabel];
    
    // 创建速度显示标签，使用表格数字
    self.velocityLabel = [[NSLabel alloc] init];
    [self.velocityLabel setStringValue:@"速度: 00 度/秒"];
    [self.velocityLabel setFont:[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightRegular]];
    [self.velocityLabel setAlignment:NSTextAlignmentCenter];
    [contentView addSubview:self.velocityLabel];
    
    // 创建状态标签
    self.statusLabel = [[NSLabel alloc] init];
    [self.statusLabel setStringValue:@"正在检测传感器..."];
    [self.statusLabel setFont:[NSFont systemFontOfSize:14]];
    [self.statusLabel setAlignment:NSTextAlignmentCenter];
    [self.statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [contentView addSubview:self.statusLabel];
    
    // 创建音频切换按钮
    self.audioToggleButton = [[NSButton alloc] init];
    [self.audioToggleButton setTitle:@"开始音频"];
    [self.audioToggleButton setBezelStyle:NSBezelStyleRounded];
    [self.audioToggleButton setTarget:self];
    [self.audioToggleButton setAction:@selector(toggleAudio:)];
    [self.audioToggleButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contentView addSubview:self.audioToggleButton];
    
    // Create audio status label
    self.audioStatusLabel = [[NSLabel alloc] init];
    [self.audioStatusLabel setStringValue:@""];
    [self.audioStatusLabel setFont:[NSFont systemFontOfSize:14]];
    [self.audioStatusLabel setAlignment:NSTextAlignmentCenter];
    [self.audioStatusLabel setTextColor:[NSColor secondaryLabelColor]];
    [contentView addSubview:self.audioStatusLabel];
    
    // Create mode label
    self.modeLabel = [[NSLabel alloc] init];
    [self.modeLabel setStringValue:@"音频模式:"];
    [self.modeLabel setFont:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium]];
    [self.modeLabel setAlignment:NSTextAlignmentCenter];
    [self.modeLabel setTextColor:[NSColor labelColor]];
    [contentView addSubview:self.modeLabel];
    
    // Create mode selector
    self.modeSelector = [[NSSegmentedControl alloc] init];
    [self.modeSelector setSegmentCount:2];
    [self.modeSelector setLabel:@"吱吱声" forSegment:0];
    [self.modeSelector setLabel:@"特雷门琴" forSegment:1];
    [self.modeSelector setSelectedSegment:0]; // Default to creak
    [self.modeSelector setTarget:self];
    [self.modeSelector setAction:@selector(modeChanged:)];
    [self.modeSelector setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contentView addSubview:self.modeSelector];
    
    // Set up auto layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Angle label (main display, now at top)
        [self.angleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:40],
        [self.angleLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.angleLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor constant:-40],
        
        // Velocity label
        [self.velocityLabel.topAnchor constraintEqualToAnchor:self.angleLabel.bottomAnchor constant:15],
        [self.velocityLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.velocityLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor constant:-40],
        
        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.velocityLabel.bottomAnchor constant:15],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor constant:-40],
        
        // Audio toggle button
        [self.audioToggleButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:25],
        [self.audioToggleButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.audioToggleButton.widthAnchor constraintEqualToConstant:120],
        [self.audioToggleButton.heightAnchor constraintEqualToConstant:32],
        
        // Audio status label
        [self.audioStatusLabel.topAnchor constraintEqualToAnchor:self.audioToggleButton.bottomAnchor constant:15],
        [self.audioStatusLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.audioStatusLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor constant:-40],
        
        // Mode label
        [self.modeLabel.topAnchor constraintEqualToAnchor:self.audioStatusLabel.bottomAnchor constant:25],
        [self.modeLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.modeLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor constant:-40],
        
        // Mode selector
        [self.modeSelector.topAnchor constraintEqualToAnchor:self.modeLabel.bottomAnchor constant:10],
        [self.modeSelector.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.modeSelector.widthAnchor constraintEqualToConstant:200],
        [self.modeSelector.heightAnchor constraintEqualToConstant:28],
        [self.modeSelector.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
}

- (void)initializeLidSensor {
    self.lidSensor = [[LidAngleSensor alloc] init];
    
    if (self.lidSensor.isAvailable) {
        [self.statusLabel setStringValue:@"已检测到传感器 - 正在读取角度..."];
        [self.statusLabel setTextColor:[NSColor systemGreenColor]];
    } else {
        [self.statusLabel setStringValue:@"此设备不支持屏幕角度传感器"];
        [self.statusLabel setTextColor:[NSColor systemRedColor]];
        [self.angleLabel setStringValue:@"不可用"];
        [self.angleLabel setTextColor:[NSColor systemRedColor]];
    }
}

- (void)initializeAudioEngines {
    self.creakAudioEngine = [[CreakAudioEngine alloc] init];
    self.thereminAudioEngine = [[ThereminAudioEngine alloc] init];
    
    if (self.creakAudioEngine && self.thereminAudioEngine) {
        [self.audioStatusLabel setStringValue:@""];
    } else {
        [self.audioStatusLabel setStringValue:@"音频初始化失败"];
        [self.audioStatusLabel setTextColor:[NSColor systemRedColor]];
        [self.audioToggleButton setEnabled:NO];
    }
}

- (IBAction)toggleAudio:(id)sender {
    id currentEngine = [self currentAudioEngine];
    if (!currentEngine) {
        return;
    }
    
    if ([currentEngine isEngineRunning]) {
        [currentEngine stopEngine];
        [self.audioToggleButton setTitle:@"开始音频"];
        [self.audioStatusLabel setStringValue:@""];
    } else {
        [currentEngine startEngine];
        [self.audioToggleButton setTitle:@"停止音频"];
        [self.audioStatusLabel setStringValue:@""];
    }
}

- (IBAction)modeChanged:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    AudioMode newMode = (AudioMode)control.selectedSegment;
    
    // 如果当前引擎正在运行则停止它
    id currentEngine = [self currentAudioEngine];
    BOOL wasRunning = [currentEngine isEngineRunning];
    if (wasRunning) {
        [currentEngine stopEngine];
    }
    
    // 更新模式
    self.currentAudioMode = newMode;
    
    // 如果之前的引擎正在运行，则启动新引擎
    if (wasRunning) {
        id newEngine = [self currentAudioEngine];
        [newEngine startEngine];
        [self.audioToggleButton setTitle:@"停止音频"];
    } else {
        [self.audioToggleButton setTitle:@"开始音频"];
    }
    
    [self.audioStatusLabel setStringValue:@""];
}

- (id)currentAudioEngine {
    switch (self.currentAudioMode) {
        case AudioModeCreak:
            return self.creakAudioEngine;
        case AudioModeTheremin:
            return self.thereminAudioEngine;
        default:
            return self.creakAudioEngine;
    }
}

- (void)startUpdatingDisplay {
    // 每 16 毫秒更新一次（60Hz），以实现平滑的实时音频和显示更新
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.016
                                                        target:self
                                                      selector:@selector(updateAngleDisplay)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)updateAngleDisplay {
    if (!self.lidSensor.isAvailable) {
        return;
    }
    
    double angle = [self.lidSensor lidAngle];
    
    if (angle == -2.0) {
        [self.angleLabel setStringValue:@"读取错误"];
        [self.angleLabel setTextColor:[NSColor systemOrangeColor]];
        [self.statusLabel setStringValue:@"无法读取传感器数据"];
        [self.statusLabel setTextColor:[NSColor systemOrangeColor]];
    } else {
        [self.angleLabel setStringValue:[NSString stringWithFormat:@"%.1f°", angle]];
        [self.angleLabel setTextColor:[NSColor systemBlueColor]];
        
        // 使用新角度更新当前音频引擎
        id currentEngine = [self currentAudioEngine];
        if (currentEngine) {
            [currentEngine updateWithLidAngle:angle];
            
            // 使用前导零和整数更新速度显示
            double velocity = [currentEngine currentVelocity];
            int roundedVelocity = (int)round(velocity);
            if (roundedVelocity < 100) {
                [self.velocityLabel setStringValue:[NSString stringWithFormat:@"速度: %02d 度/秒", roundedVelocity]];
            } else {
                [self.velocityLabel setStringValue:[NSString stringWithFormat:@"速度: %d 度/秒", roundedVelocity]];
            }
            
            // 运行时显示音频参数
            if ([currentEngine isEngineRunning]) {
                if (self.currentAudioMode == AudioModeCreak) {
                    double gain = [currentEngine currentGain];
                    double rate = [currentEngine currentRate];
                    [self.audioStatusLabel setStringValue:[NSString stringWithFormat:@"增益: %.2f, 速率: %.2f", gain, rate]];
                } else if (self.currentAudioMode == AudioModeTheremin) {
                    double frequency = [currentEngine currentFrequency];
                    double volume = [currentEngine currentVolume];
                    [self.audioStatusLabel setStringValue:[NSString stringWithFormat:@"频率: %.1f Hz, 音量: %.2f", frequency, volume]];
                }
            }
        }
        
        // 根据角度提供上下文状态
        NSString *status;
        if (angle < 5.0) {
            status = @"屏幕已关闭";
        } else if (angle < 45.0) {
            status = @"屏幕微开";
        } else if (angle < 90.0) {
            status = @"屏幕半开";
        } else if (angle < 120.0) {
            status = @"屏幕大部分打开";
        } else {
            status = @"屏幕完全打开";
        }
        
        [self.statusLabel setStringValue:status];
        [self.statusLabel setTextColor:[NSColor secondaryLabelColor]];
    }
}

@end
