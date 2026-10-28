// 场景控制子文件：把菜单的云层覆盖、密度与雾系数原样抄到输出。
// 调用位置：由 `post/scene.slang` 内联；需要复现 Eclipse `scene_controller.glsl` 默认值的程序调用下面两个入口。
// 设计原因与取舍：这里没有算法，只有接口映射；单独成文件是为了让画面效果文件只留受伤、入水与着火。
// 可复制示例：`ogxSceneControllerDefaults(outSmallCoverage, outSmallDensity, outLargeCoverage, outLargeDensity, outAltostratusCoverage, outAltostratusDensity, outCirrusCoverage, outCirrusDensity, outFogA, outFogB);`

// 场景控制参数：没有自定义触发器时，把所有天气与云层参数原样输出。
void ogxSceneControllerParameters(float smallCumulusCoverage, float smallCumulusDensity,
    float largeCumulusCoverage, float largeCumulusDensity, float altostratusCoverage,
    float altostratusDensity, float cirrusCoverage, float cirrusDensity,
    out float outSmallCoverage, out float outSmallDensity, out float outLargeCoverage,
    out float outLargeDensity, out float outAltostratusCoverage, out float outAltostratusDensity,
    out float outCirrusCoverage, out float outCirrusDensity, out float fogA, out float fogB)
{
    outSmallCoverage = smallCumulusCoverage; // 小积云覆盖。
    outSmallDensity = smallCumulusDensity; // 小积云密度。
    outLargeCoverage = largeCumulusCoverage; // 大积云覆盖。
    outLargeDensity = largeCumulusDensity; // 大积云密度。
    outAltostratusCoverage = altostratusCoverage; // 高层云覆盖。
    outAltostratusDensity = altostratusDensity; // 高层云密度。
    outCirrusCoverage = cirrusCoverage; // 卷云覆盖。
    outCirrusDensity = cirrusDensity; // 卷云密度。
    fogA = 1.0; // 均匀雾倍率。
    fogB = 1.0; // 云雨雾倍率。
}

// 场景控制器的默认参数：把云层覆盖与密度写进输出，雾系数固定为一。
// 参考签名只有十个输出；库版本不再接收额外输入，直接给出参考默认值。
void ogxSceneControllerDefaults(out float smallCumulusCoverage, out float smallCumulusDensity,
    out float largeCumulusCoverage, out float largeCumulusDensity, out float altostratusCoverage,
    out float altostratusDensity, out float cirrusCoverage, out float cirrusDensity,
    out float fogA, out float fogB)
{
    smallCumulusCoverage = 1.0; // 默认满覆盖。
    smallCumulusDensity = 0.5; // 小积云中等密度。
    largeCumulusCoverage = 1.0; // 大积云满覆盖。
    largeCumulusDensity = 0.6; // 大积云略浓。
    altostratusCoverage = 0.6; // 高层云六成覆盖。
    altostratusDensity = 0.1; // 高层云很薄。
    cirrusCoverage = 0.07; // 卷云稀疏。
    cirrusDensity = 0.005; // 卷云几乎透明。
    fogA = 1.0; // 均匀雾倍率中性。
    fogB = 1.0; // 云雨雾倍率中性。
}
