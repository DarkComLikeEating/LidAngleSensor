//
//  ThereminAudioEngine.h
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/**
 * ThereminAudioEngine 提供响应 MacBook 屏幕角度变化的实时特雷门琴式音频。
 * 
 * 功能特性：
 * - 基于屏幕角度的实时正弦波合成
 * - 平滑的频率转换以避免音频失真
 * - 基于角速度的音量控制
 * - 可配置的频率范围映射
 * - 低延迟音频生成
 * 
 * 音频行为：
 * - 屏幕角度映射到频率（关闭 = 低音调，打开 = 高音调）
 * - 移动速度控制音量（慢速移动 = 响亮，快速移动 = 安静）
 * - 平滑的参数插值以获得音乐品质
 */
@interface ThereminAudioEngine : NSObject

@property (nonatomic, assign, readonly) BOOL isEngineRunning;
@property (nonatomic, assign, readonly) double currentVelocity;
@property (nonatomic, assign, readonly) double currentFrequency;
@property (nonatomic, assign, readonly) double currentVolume;

/**
 * 初始化特雷门琴音频引擎。
 * @return 初始化的引擎实例，如果初始化失败则返回 nil
 */
- (instancetype)init;

/**
 * 启动音频引擎并开始生成音调。
 */
- (void)startEngine;

/**
 * 停止音频引擎并停止生成音调。
 */
- (void)stopEngine;

/**
 * 根据新的屏幕角度测量值更新特雷门琴音频。
 * 该方法计算基于移动的频率映射和音量。
 * @param lidAngle 当前屏幕角度（以度为单位）
 */
- (void)updateWithLidAngle:(double)lidAngle;

/**
 * 手动设置角速度（用于测试目的）。
 * @param velocity 角速度（以度/秒为单位）
 */
- (void)setAngularVelocity:(double)velocity;

@end
