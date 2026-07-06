# 项目名称
HarmonyOS 类社交媒体应用

[![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-5.0+-brightgreen)](https://developer.harmonyos.com/)
[![DevEco Studio](https://img.shields.io/badge/DevEco%20Studio-4.0+-blueviolet)](https://developer.harmonyos.com/cn/develop/deveco-studio)

> **项目一句话描述**：一款基于 HarmonyOS 的轻量化分布式图文社交应用，支持图文发布、AI智能识图分类和分布式多设备协同互动。[reference:4][reference:5]

## 📖 目录

- [项目简介](#-项目简介)
- [功能特性](#-功能特性)
- [项目截图](#-项目截图)
- [技术栈](#-技术栈)
- [快速开始](#-快速开始)
- [项目结构](#-项目结构)
- [开发规范](#-开发规范)


## 📝 项目简介

### 项目背景

随着 HarmonyOS 分布式生态的完善，跨设备协同成为移动应用的重要方向；同时，端侧轻量化 AI 推理技术已能在本地完成图像识别等任务。现有简易社交应用大多仅支持单设备使用，缺少跨终端数据互通能力，且图像管理依赖人工归类，用户操作成本高。[reference:6]

### 项目目标

本项目基于 HarmonyOS、ArkTS 与 MindSpore Lite，开发一款轻量化分布式图文社交软件，核心实现：

1. **图文发布功能**：支持用户上传本地图片、编辑配套文字内容并完成发布。
2. **AI 智能识图分类**：搭载轻量化本地 AI 模型，自动识别上传图片内容并完成分类归档。
3. **分布式多设备协同互动**：依托鸿蒙分布式特性，实现多终端数据互通、跨设备浏览内容与评论互动。[reference:7]

### 适用场景

搭载 HarmonyOS 系统的手机、平板、智慧屏等终端设备，支持多台鸿蒙设备在局域网内互联，实现一人发布、多端同步浏览、评论互动。[reference:8]

## ✨ 功能特性

- 🔄 **跨设备协同**：利用鸿蒙分布式软总线，实现多设备自动发现、互联与数据实时同步[reference:9]。
- 🤖 **AI 智能识图**：采用 MindSpore Lite 轻量化推理框架，在本地完成图片分类，兼顾效率与隐私[reference:10]。
- 🖼️ **图文发布**：支持图片上传、文字编辑与内容发布。
- 🏷️ **分类浏览**：根据 AI 识别结果自动归档，支持按分类筛选查看。
- 💬 **互动评论**：支持跨设备浏览内容与评论互动。
- 📥 **图片下载**：支持一键下载图片到本地。

## 📱 项目截图

> **提示**：在 `images/` 目录下放入截图，然后用 `![描述](images/截图文件名.png)` 引用。

| 首页 | 发布页 | 分类浏览 |
| :---: | :---: | :---: |
| ![首页](images/home.png) | ![发布](images/publish.png) | ![分类](images/category.png) |

## 🛠️ 技术栈

- **开发工具**：DevEco Studio 4.0+[reference:11]
- **开发语言**：ArkTS[reference:12]
- **操作系统**：HarmonyOS 5.0+[reference:13]
- **AI 推理框架**：MindSpore Lite[reference:14]
- **分布式能力**：HarmonyOS 分布式软总线[reference:15]

## 🚀 快速开始

以下步骤将引导你在本地环境搭建并运行本项目。[reference:16]

### 前提条件

在开始前，请确保你的开发环境满足以下要求：[reference:17]

- [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio) 4.0 或以上版本[reference:18]
- HarmonyOS SDK API 10+[reference:19]
- [Node.js](https://nodejs.org/) 18.0 或以上版本[reference:20]
- 一台 HarmonyOS 真机或已创建的模拟器

### 安装步骤

1.  **克隆项目**：
    ```bash
    git clone https://github.com/你的用户名/你的仓库名.git
