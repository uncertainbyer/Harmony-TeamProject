# 项目名称
HarmonyOS 类社交媒体应用

[![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-5.0+-brightgreen)](https://developer.harmonyos.com/)
[![DevEco Studio](https://img.shields.io/badge/DevEco%20Studio-4.0+-blueviolet)](https://developer.harmonyos.com/cn/develop/deveco-studio)

> **项目一句话描述**：一款基于 HarmonyOS 的轻量化分布式图文社交应用，支持图文发布、AI智能识图分类和分布式多设备协同互动。

## 📖 目录

- [项目简介](#-项目简介)
- [功能特性](#-功能特性)
- [项目截图](#-项目截图)
- [技术栈](#-技术栈)
- [快速开始](#-快速开始)
- [许可证](#-许可证)

## 📝 项目简介

### 项目背景

随着 HarmonyOS 分布式生态的完善，跨设备协同成为移动应用的重要方向；同时，端侧轻量化 AI 推理技术已能在本地完成图像识别等任务。现有简易社交应用大多仅支持单设备使用，缺少跨终端数据互通能力，且图像管理依赖人工归类，用户操作成本高。

### 项目目标

本项目基于 HarmonyOS、ArkTS 与 MindSpore Lite，开发一款轻量化分布式图文社交软件，核心实现：

1. **图文发布功能**：支持用户上传本地图片、编辑配套文字内容并完成发布。
2. **AI 智能识图分类**：搭载轻量化本地 AI 模型，自动识别上传图片内容并完成分类归档。
3. **分布式多设备协同互动**：依托鸿蒙分布式特性，实现多终端数据互通、跨设备浏览内容与评论互动。

### 适用场景

搭载 HarmonyOS 系统的手机、平板、智慧屏等终端设备，支持多台鸿蒙设备在局域网内互联，实现一人发布、多端同步浏览、评论互动。

## ✨ 功能特性

- 🔄 **跨设备协同**：利用鸿蒙分布式软总线，实现多设备自动发现、互联与数据实时同步。
- 🤖 **AI 智能识图**：采用 MindSpore Lite 轻量化推理框架，在本地完成图片分类，兼顾效率与隐私。
- 🖼️ **图文发布**：支持图片上传、文字编辑与内容发布。
- 🏷️ **分类浏览**：根据 AI 识别结果自动归档，支持按分类筛选查看。
- 💬 **互动评论**：支持跨设备浏览内容与评论互动。
- 📥 **图片下载**：支持一键下载图片到本地。

## 📱 项目截图

> **提示**：请将运行截图放入 `images/` 目录下，然后取消下面示例行的注释并替换文件名。  
> 若暂无截图，可暂时删除此章节或保留占位说明。

<!-- 示例（取消注释并替换文件名）：
| 首页 | 发布页 | 分类浏览 |
| :---: | :---: | :---: |
| ![首页](images/home.png) | ![发布](images/publish.png) | ![分类](images/category.png) |
-->

*（截图待补充）*

---

## 🛠️ 技术栈

- **开发工具**：DevEco Studio 4.0+
- **开发语言**：ArkTS
- **操作系统**：HarmonyOS 5.0+
- **AI 推理框架**：MindSpore Lite
- **分布式能力**：HarmonyOS 分布式软总线

## 🚀 快速开始

分布式同步的架构、双真机连接与演示步骤见
[`docs/distributed-sync.md`](docs/distributed-sync.md)。

以下步骤将引导你在本地环境搭建并运行本项目。

### 前提条件

在开始前，请确保你的开发环境满足以下要求：

- [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio) 4.0 或以上版本
- HarmonyOS SDK API 10+
- [Node.js](https://nodejs.org/) 18.0 或以上版本
- 一台 HarmonyOS 真机或已创建的模拟器

### 安装步骤

1.  **克隆项目**：
    ```bash
    git clone https://github.com/你的用户名/你的仓库名.git
2.  **打开项目**：
    启动 DevEco Studio，选择 Open，然后选中刚才克隆下来的项目文件夹。
3.  **配置签名（如需要）**：
    如需在真机上运行，请将签名文件放入 signature/ 目录，并修改 build-profile.json5 中的签名配置。
4.  **同步依赖**：
    DevEco Studio 会自动同步项目依赖（位于 oh_modules/）。如未自动开始，可点击右上角的 Sync Now。
5.  **运行项目**：
    - 连接真机或启动模拟器。
    - 点击工具栏的 运行 按钮（▶️）。
    - 等待编译完成，应用将自动安装并启动。

### 📄 许可证

本项目采用 MIT License 进行许可。详见仓库根目录下的 LICENSE 文件。
