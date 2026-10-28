// 末地星空子文件：按天球格子取哈希星点，星色用黑体温度。
// 调用位置：由 `world/end.slang` 内联；末地天空与吸积盘叠加都调用 `ogxEndStars`。
// 设计原因与取舍：星场只依赖方向、时间与太阳方向，旋转与色温都来自通用数学，可单独测试。
// 可复制示例：`float3 stars = ogxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);`

// iterationT 末地星空：先绕纵轴缓慢自转，再把天球对齐太阳轴，最后在格子里取星点。
// `starType`、`brightness`、`amount` 是参考签名的三个开关；当前星场只用到前两个，保留参数以便严格对照。
float3 ogxEndStars(float3 worldDir, float3 worldSunVector, float time, int starType, float brightness, float amount)
{
    float angleY = time * 0.001; // 星空缓慢自转。
    float3x3 eyeRotationY = ogxRotationY(angleY); // 绕纵轴旋转。
    worldDir = ogxMatrix3MulPoint(eyeRotationY, worldDir); // 转到星空坐标。
    const float scale = 384.0; // 星点密度。
    const float coverage = 0.007; // 星点覆盖率。
    const float maxLuminance = 0.04; // 单颗星最大亮度。
    const float minTemperature = 4000.0; // 最低色温。
    const float maxTemperature = 8000.0; // 最高色温。
    float cosine = dot(worldSunVector, float3(0.0, 0.0, 1.0)); // 绕日轴对齐。
    float3 axis = cross(worldSunVector, float3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 轴长度倒数平方。
    worldDir = cosine * worldDir + cross(axis, worldDir)
        + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 参考实现的球面旋转。
    float3 p = worldDir * scale; // 放大到格子。
    float3 i = floor(p); // 格子下标。
    float3 f = p - i; // 格内偏移。
    float r = dot(f - 0.5, f - 0.5); // 到格中心距离平方。
    float3 i3 = fract(i * float3(443.897, 441.423, 437.195)); // 三维哈希。
    i3 += dot(i3, i3.yzx + 19.19); // 二次混合。
    float2 hash = fract((i3.xx + i3.yz) * i3.zy); // 两个哈希值。
    hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 亮度曲线。
    float c = ogxRemapSaturate(hash.x, 1.0 - coverage, 1.0); // 覆盖率阈值。
    return maxLuminance * ogxRemapSaturate(r, 0.25, 0.0) * c * c * ogxBlackbody(lerp(minTemperature, maxTemperature, hash.y)); // 星点亮度乘色温。
}
