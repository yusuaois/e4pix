// HDR 融合与图像对齐的共享常量

// ITU-R BT.601 亮度系数
const double kLumaR = 0.299;
const double kLumaG = 0.587;
const double kLumaB = 0.114;

/// 进度阶段边界（对话框绝对进度）
const double kProgressDecodeEnd = 0.3;
const double kProgressAlignEnd = 0.5;
const double kProgressFusionEnd = 0.86;
const double kProgressSaveStart = 0.9;
