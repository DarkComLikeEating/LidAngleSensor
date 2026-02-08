//
//  LidAngleSensor.h
//  LidAngleSensor
//
//  Created by Sam on 2025-09-06.
//

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDDevice.h>

/**
 * LidAngleSensor 提供对 MacBook 内置屏幕倾角传感器的访问。
 * 
 * 该类与 HID 设备接口，报告笔记本电脑屏幕与底座之间的角度，
 * 提供实时的角度测量值（以度为单位）。
 * 
 * 设备规格（通过逆向工程发现）：
 * - Apple 设备：VID=0x05AC, PID=0x8104
 * - HID 用途：传感器页面 (0x0020)，方向用途 (0x008A)
 * - 数据格式：16 位角度值，单位为百分之一度（0.01° 分辨率）
 * - 范围：0-360 度
 */
@interface LidAngleSensor : NSObject

@property (nonatomic, assign, readonly) IOHIDDeviceRef hidDevice;
@property (nonatomic, assign, readonly) BOOL isAvailable;

/**
 * 初始化并连接到屏幕倾角传感器。
 * @return 初始化的传感器实例，如果传感器不可用则返回 nil
 */
- (instancetype)init;

/**
 * 读取当前的屏幕倾角。
 * @return 角度（0-360 度），如果读取失败则返回 -2.0
 */
- (double)lidAngle;

/**
 * 开始监控屏幕倾角（在 init 中自动调用）。
 */
- (void)startLidAngleUpdates;

/**
 * 停止监控屏幕倾角并释放资源。
 */
- (void)stopLidAngleUpdates;

@end
