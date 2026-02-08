# MacBook 屏幕倾角检测器

这是一个实用工具程序，用于显示 MacBook 内置屏幕倾角传感器的角度值。程序还提供了两种可选的音频反馈模式：
- **门吱吱声模式**：当你缓慢调整屏幕角度时，会播放木门吱吱作响的声音
- **特雷门琴模式**：屏幕角度控制音高，移动速度控制音量，带来音乐般的体验

## 常见问题

**什么是屏幕倾角传感器？**

这是一个可以检测 MacBook 屏幕盖与底座之间角度的传感器。

**哪些设备有屏幕倾角传感器？**

该传感器最早出现在 2019 年的 16 英寸 MacBook Pro 上。如果你的笔记本电脑更新，大概率会有这个传感器。[根据反馈](https://github.com/samhenrigold/LidAngleSensor/issues/13)，**M1 设备可能无法正常工作**。

**我的笔记本应该有这个传感器，为什么检测不到？**

如果你的设备应该支持但无法检测到，可以尝试运行[这个脚本](https://gist.github.com/samhenrigold/42b5a92d1ee8aaf2b840be34bff28591)来诊断问题，并在 [issue](https://github.com/samhenrigold/LidAngleSensor/issues/new/choose) 中反馈结果。

已知存在问题的型号：

- M1 MacBook Air
- M1 MacBook Pro

**可以在 iMac 上使用吗？**

根据[测试反馈](https://github.com/samhenrigold/LidAngleSensor/issues/33)，iMac 也可以正常工作。

**为什么笔记本电脑需要知道屏幕的精确角度？**

这个问题暂无确切答案。

**可以关闭声音吗？**

可以，不点击"Start Audio"按钮即可。

## 编译

根据[此 issue](https://github.com/samhenrigold/LidAngleSensor/issues/12)，编译此项目需要安装 Xcode。建议使用 Xcode 16 或更高版本。

## 安装

通过 Homebrew 安装：

```shell
brew install lidanglesensor
```

## 相关项目

- [Python 库：pybooklid](https://github.com/tcsenpai/pybooklid)
