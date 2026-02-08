//
//  CreakAudioEngine.h
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/**
 * CreakAudioEngine 提供响应 MacBook 屏幕角度变化的实时门吱吱声音频。
 * 
 * 功能特性：
 * - 实时角速度计算，具有多级噪声过滤
 * - 基于移动速度的动态增益和音高/速度映射
 * - 平滑的参数斜坡以避免音频失真
 * - 死区以防止微小移动时的抖动
 * - 优化的低延迟、响应式音频反馈
 * 
 * 音频行为：
 * - 慢速移动（1-10 度/秒）：最大吱吱声音量
 * - 中速移动（10-100 度/秒）：逐渐淡出至静音
 * - 快速移动（100+ 度/秒）：静音
 */
@interface CreakAudioEngine : NSObject

@property (nonatomic, assign, readonly) BOOL isEngineRunning;
@property (nonatomic, assign, readonly) double currentVelocity;
@property (nonatomic, assign, readonly) double currentGain;
@property (nonatomic, assign, readonly) double currentRate;

/**
 * 初始化音频引擎并加载音频文件。
 * @return 初始化的引擎实例，如果初始化失败则返回 nil
 */
- (instancetype)init;

/**
 * 启动音频引擎并开始播放。
 */
- (void)startEngine;

/**
 * 停止音频引擎并暂停播放。
 */
- (void)stopEngine;

/**
 * 根据新的屏幕角度测量值更新吱吱声音频。
 * 该方法计算角速度，应用平滑处理，并更新音频参数。
 * @param lidAngle 当前屏幕角度（以度为单位）
 */
- (void)updateWithLidAngle:(double)lidAngle;

/**
 * 手动设置角速度（用于测试目的）。
 * @param velocity 角速度（以度/秒为单位）
 */
- (void)setAngularVelocity:(double)velocity;

@end
