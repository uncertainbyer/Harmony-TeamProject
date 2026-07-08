import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { Logger } from '../utils/Logger';

const TAG: string = 'ModelInference';

/**
 * 模型推理配置接口
 */
export interface InferenceConfig {
  /** 运行设备 */
  target: string[];
  /** CPU 线程数 */
  threadNum: number;
  /** 线程绑定模式 */
  threadAffinityMode: number;
  /** 精度模式 */
  precisionMode: string;
}

/**
 * 默认推理配置
 */
const DEFAULT_CONFIG: InferenceConfig = {
  target: ['cpu'],
  threadNum: 2,
  threadAffinityMode: 1,
  precisionMode: 'enforce_fp32',
};

/**
 * 基于 MindSpore Lite 的模型推理函数
 *
 * 从 ArrayBuffer 加载模型，配置推理上下文，设置输入数据并执行推理。
 *
 * @param modelBuffer - 包含模型二进制数据的 ArrayBuffer
 * @param inputsBuffer - 模型输入数据数组，每个元素对应一个输入张量
 * @param config - 可选的推理配置，未提供时使用默认配置
 * @returns 推理结果，类型为 MSTensor[]
 */
export async function modelPredict(
  modelBuffer: ArrayBuffer,
  inputsBuffer: ArrayBuffer[],
  config?: InferenceConfig
): Promise<mindSporeLite.MSTensor[]> {
  const logger: Logger = Logger.create(TAG);
  const finalConfig: InferenceConfig = config ?? DEFAULT_CONFIG;

  try {
    // 构建推理上下文
    const context: mindSporeLite.Context = {
      target: finalConfig.target,
    };

    if (finalConfig.target.indexOf('cpu') >= 0) {
      context.cpu = {
        threadNum: finalConfig.threadNum,
        threadAffinityMode: finalConfig.threadAffinityMode,
        precisionMode: finalConfig.precisionMode,
      };
    }

    logger.info('MS_LITE_LOG: Loading model from buffer, size=' + modelBuffer.byteLength);

    // 从缓冲区加载模型
    const msLiteModel: mindSporeLite.Model =
      await mindSporeLite.loadModelFromBuffer(modelBuffer, context);

    // 获取模型输入张量并设置数据
    const modelInputs: mindSporeLite.MSTensor[] = msLiteModel.getInputs();
    for (let i: number = 0; i < inputsBuffer.length; i++) {
      const inputBuffer: ArrayBuffer | null = inputsBuffer[i];
      if (inputBuffer !== null) {
        modelInputs[i].setData(inputBuffer as ArrayBuffer);
      }
    }

    logger.info('MS_LITE_LOG: Starting model inference');

    // 执行推理
    const modelOutputs: mindSporeLite.MSTensor[] =
      await msLiteModel.predict(modelInputs);

    logger.info('MS_LITE_LOG: Model inference completed successfully');

    return modelOutputs;
  } catch (err) {
    const errorMsg: string = (err as Error).message;
    logger.error('MS_LITE_ERR: Model inference failed: ' + errorMsg);
    throw new Error('MindSpore Lite 推理失败: ' + errorMsg);
  }
}

export default modelPredict;