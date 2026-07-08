import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';
import { AIConstants } from '../common/Constants';
import { modelPredict } from '../ai/ModelInference';

const TAG: string = 'AIClassifyService';

/**
 * AI 单条预测结果
 */
export interface AIPrediction {
  /** 原始标签索引 */
  labelIndex: number;
  /** 原始标签名称 */
  labelName: string;
  /** 置信度 (0-100) */
  confidence: number;
}

/**
 * AI 分类结果
 * 供前端"分类筛选"功能直接使用
 */
export interface AIClassifyResult {
  /** App 分类 ID（如 cat_scenery） */
  categoryId: string;
  /** App 分类名称（如 风景） */
  categoryName: string;
  /** 分类置信度 (0-100) */
  confidence: number;
  /** Top-K 预测结果列表 */
  topPredictions: AIPrediction[];
  /** 是否推理成功 */
  success: boolean;
  /** 错误信息（成功时为空） */
  errorMsg: string;
}

/**
 * App 分类 ID → 分类名称映射
 */
const CATEGORY_NAME_MAP: Record<string, string> = {
  'cat_scenery': '风景',
  'cat_person': '人物',
  'cat_food': '美食',
  'cat_animal': '动物',
  'cat_building': '建筑',
  'cat_other': '其他',
};

/**
 * 内部使用的带索引的值类型
 */
interface IndexedValue {
  index: number;
  value: number;
}

/**
 * AI 图像分类服务
 *
 * 封装 MindSpore Lite 推理全流程，包括：
 * 1. 图像预处理（缩放、裁剪、归一化、通道转换）
 * 2. 模型推理
 * 3. 结果解析与分类映射
 *
 * 供前端直接调用，返回标准化分类结果
 */
export class AIClassifyService {
  private static instance: AIClassifyService | null = null;
  private modelBuffer: ArrayBuffer | null = null;
  private isModelLoaded: boolean = false;
  private logger: Logger = Logger.create(TAG);

  private constructor() {
  }

  /**
   * 获取单例实例
   */
  static getInstance(): AIClassifyService {
    if (AIClassifyService.instance === null) {
      AIClassifyService.instance = new AIClassifyService();
    }
    return AIClassifyService.instance;
  }

  /**
   * 预加载 AI 模型
   * 在应用启动时调用，提前加载模型以加快首次推理速度
   *
   * @param context 应用上下文
   */
  async preloadModel(context: common.UIAbilityContext): Promise<void> {
    if (this.isModelLoaded) {
      this.logger.info('Model already loaded, skipping preload');
      return;
    }

    try {
      const resMgr: resourceManager.ResourceManager =
        context.getApplicationContext().resourceManager;
      const rawBuffer: Uint8Array =
        await resMgr.getRawFileContent(AIConstants.MODEL_NAME);
      this.modelBuffer = rawBuffer.buffer.slice(0);
      this.isModelLoaded = true;
      this.logger.info('Model preloaded successfully, size=' + this.modelBuffer.byteLength);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      this.logger.error('Failed to preload model: ' + errorMsg);
      this.isModelLoaded = false;
    }
  }

  /**
   * 检查模型是否已加载
   */
  isReady(): boolean {
    return this.isModelLoaded && this.modelBuffer !== null;
  }

  /**
   * 对 PixelMap 图像进行 AI 分类
   *
   * @param pixelMap - 待分类的 PixelMap 图像
   * @returns AI 分类结果
   */
  async classifyImage(pixelMap: image.PixelMap): Promise<AIClassifyResult> {
    const result: AIClassifyResult = {
      categoryId: 'cat_other',
      categoryName: '其他',
      confidence: 0,
      topPredictions: [],
      success: false,
      errorMsg: '',
    };

    if (!this.isModelLoaded || this.modelBuffer === null) {
      result.errorMsg = 'AI 模型未加载，请先调用 preloadModel';
      this.logger.error(result.errorMsg);
      return result;
    }

    try {
      // 1. 图像预处理
      const float32View: Float32Array = await this.preprocessImage(pixelMap);

      // 2. 执行推理
      const inputs: ArrayBuffer[] = [float32View.buffer];
      const outputs = await modelPredict(this.modelBuffer, inputs);

      // 3. 解析输出结果
      if (outputs.length === 0) {
        result.errorMsg = '模型推理未返回结果';
        return result;
      }

      const outputTensor = outputs[0];
      const outputData: Float32Array = new Float32Array(outputTensor.getData());
      const topPredictions: AIPrediction[] = this.extractTopK(outputData, AIConstants.TOP_K);

      result.topPredictions = topPredictions;

      if (topPredictions.length === 0) {
        result.errorMsg = '未能提取有效分类结果';
        this.logger.warn(result.errorMsg);
        return result;
      }

      // 4. 映射到 App 分类
      const bestPrediction: AIPrediction = topPredictions[0];
      const labelName: string = bestPrediction.labelName;
      const categoryId: string = this.mapLabelToCategory(labelName, bestPrediction.confidence);

      result.categoryId = categoryId;
      result.categoryName = CATEGORY_NAME_MAP[categoryId] ?? '其他';
      result.confidence = bestPrediction.confidence;
      result.success = true;

      this.logger.info(
        'Classification result: ' +
        'label=' + labelName +
        ', category=' + result.categoryName +
        ', confidence=' + result.confidence + '%'
      );

      return result;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      result.errorMsg = 'AI 分类失败: ' + errorMsg;
      this.logger.error(result.errorMsg);
      return result;
    }
  }

  /**
   * 从文件 URI 加载图像并进行 AI 分类
   *
   * @param uri - 图像文件 URI
   * @returns AI 分类结果
   */
  async classifyImageFromUri(uri: string): Promise<AIClassifyResult> {
    const result: AIClassifyResult = {
      categoryId: 'cat_other',
      categoryName: '其他',
      confidence: 0,
      topPredictions: [],
      success: false,
      errorMsg: '',
    };

    try {
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const imageSource: image.ImageSource = image.createImageSource(file.fd);
      const pixelMap: image.PixelMap = await imageSource.createPixelMap();
      fileIo.closeSync(file);

      return await this.classifyImage(pixelMap);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      result.errorMsg = '从 URI 加载图像失败: ' + errorMsg;
      this.logger.error(result.errorMsg);
      return result;
    }
  }

  /**
   * 图像预处理：缩放 → 裁剪 → 归一化 → 通道转换
   *
   * 将输入图像处理为模型所需的 224×224×3 Float32 张量
   *
   * @param pixelMap - 原始 PixelMap
   * @returns Float32Array 格式的张量数据
   */
  private async preprocessImage(pixelMap: image.PixelMap): Promise<Float32Array> {
    const pixelCount: number = AIConstants.MODEL_INPUT_HEIGHT * AIConstants.MODEL_INPUT_WIDTH;
    const channelCount: number = 3;

    // 获取原始图像信息
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    this.logger.info('Original image size: ' + info.size.width + 'x' + info.size.height);

    // 缩放：将图像缩放到 MAX_ZOOM_VALUE，使短边对齐
    const widthRatio: number = AIConstants.MAX_ZOOM_VALUE / info.size.width;
    const heightRatio: number = AIConstants.MAX_ZOOM_VALUE / info.size.height;
    const scaleRatio: number = Math.max(widthRatio, heightRatio);

    await pixelMap.scale(scaleRatio, scaleRatio);

    // 裁剪：从 (CROP_X, CROP_Y) 开始裁剪 MODEL_INPUT_WIDTH × MODEL_INPUT_HEIGHT
    await pixelMap.crop({
      x: AIConstants.CROP_X,
      y: AIConstants.CROP_Y,
      size: {
        height: AIConstants.MODEL_INPUT_HEIGHT,
        width: AIConstants.MODEL_INPUT_WIDTH,
      },
    });

    const cropInfo: image.ImageInfo = await pixelMap.getImageInfo();
    this.logger.info(
      'Cropped image size: ' + cropInfo.size.width + 'x' + cropInfo.size.height
    );

    // 读取像素数据（RGBA 格式，每像素 4 字节）
    const readBuffer: ArrayBuffer = new ArrayBuffer(pixelCount * 4);
    await pixelMap.readPixelsToBuffer(readBuffer);
    const imageArr: Uint8Array = new Uint8Array(readBuffer);

    this.logger.info('Pixel data read, buffer length: ' + imageArr.length);

    // 转换为 Float32Array 并进行归一化
    // 通道顺序：RGBA → BGR（模型期望 BGR 输入）
    const float32View: Float32Array = new Float32Array(pixelCount * channelCount);
    let index: number = 0;

    for (let i: number = 0; i < imageArr.length; i++) {
      // 跳过 Alpha 通道（每 4 字节的第 4 个字节）
      if ((i + 1) % 4 === 0) {
        // B 通道 (i-3)：BGRA 中的 Blue
        float32View[index] =
          (imageArr[i - 3] / AIConstants.RGB_MAX - AIConstants.MEANS[0]) /
          AIConstants.STDS[0];
        // G 通道 (i-2)：BGRA 中的 Green
        float32View[index + 1] =
          (imageArr[i - 2] / AIConstants.RGB_MAX - AIConstants.MEANS[1]) /
          AIConstants.STDS[1];
        // R 通道 (i-1)：BGRA 中的 Red
        float32View[index + 2] =
          (imageArr[i - 1] / AIConstants.RGB_MAX - AIConstants.MEANS[2]) /
          AIConstants.STDS[2];
        index += 3;
      }
    }

    this.logger.info('Preprocessing completed, tensor size: ' + float32View.length);

    return float32View;
  }

  /**
   * 从输出 logits 中提取 Top-K 预测结果
   *
   * @param outputData - 模型输出的 Float32Array
   * @param k - 返回前 K 个结果
   * @returns Top-K 预测列表
   */
  private extractTopK(outputData: Float32Array, k: number): AIPrediction[] {
    // 创建带索引的数组
    const indexed: IndexedValue[] = [];
    for (let i: number = 0; i < outputData.length; i++) {
      const item: IndexedValue = { index: i, value: outputData[i] };
      indexed.push(item);
    }

    // 按置信度降序排序
    indexed.sort((a: IndexedValue, b: IndexedValue): number => b.value - a.value);

    // 提取 Top-K
    const predictions: AIPrediction[] = [];
    const labels: string[] = AIConstants.LABELS_NAME_MAP;

    for (let i: number = 0; i < Math.min(k, indexed.length); i++) {
      const labelIndex: number = indexed[i].index;
      const confidence: number = Math.round(indexed[i].value * AIConstants.TEN_THOUSAND) / 100;
      const labelName: string = labelIndex < labels.length ? labels[labelIndex] : 'Unknown';

      predictions.push({
        labelIndex: labelIndex,
        labelName: labelName,
        confidence: confidence,
      });
    }

    return predictions;
  }

  /**
   * 将模型标签映射到 App 分类
   *
   * 优先使用关键词精确匹配，若置信度低于阈值则归入"其他"
   *
   * @param labelName - 模型输出的标签名称
   * @param confidence - 置信度
   * @returns App 分类 ID
   */
  private mapLabelToCategory(labelName: string, confidence: number): string {
    // 置信度低于阈值时归入"其他"
    if (confidence < AIConstants.CONFIDENCE_THRESHOLD * 100) {
      return 'cat_other';
    }

    // 使用关键词匹配
    const categoryId: string = AIConstants.getCategoryForLabelName(labelName);
    return categoryId;
  }

  /**
   * 释放模型资源
   */
  release(): void {
    this.modelBuffer = null;
    this.isModelLoaded = false;
    this.logger.info('Model resources released');
  }
}

export default AIClassifyService;