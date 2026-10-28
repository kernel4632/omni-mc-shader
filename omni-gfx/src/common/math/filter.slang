// 数学模块纹理过滤：双线性、天空盒图集双线性、三次 B 样条与双三次采样。
// 调用位置：由 `common/math.slang` 内联引入，采样器与坐标由调用方传入。
// 可复制示例：`float4 c = ogxBilinearTexture(tex, uv, texSize);`
// 设计原因与取舍：库不绑定任何纹理单元；取像素与层级采样都显式写在参数里。

// --- 纹理过滤与双三次采样 ---

// 双线性取像素：自己取四个相邻纹素再插值，不依赖硬件的线性过滤。
// 为什么不用 `SampleLevel`：像素画风格的月亮贴图会把硬件过滤设成最近邻，画面上出现锯齿；
// 按纹素中心取四次再按小数偏移插值，既保留最近邻的锐利，又能随屏幕坐标平滑移动。
// `coord` 是零到一的贴图坐标，`texSize` 是贴图边长（纹素）。
float4 ogxBilinearTexture(Sampler2D tex, float2 coord, float2 texSize)
{
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    float2 p = floor(coord); // 左下最近纹素。
    float2 f = coord - p; // 到该纹素的小数偏移，就是插值权重。
    int2 texelX = int2(p); // 四个纹素里左下的整数坐标。
    int2 texelW = texelX + int2(1); // 右上的整数坐标。
    float4 bottom = lerp(tex.Load(int3(texelX, 0)), tex.Load(int3(int2(texelW.x, texelX.y), 0)), f.x); // 先横向插值下排。
    float4 top = lerp(tex.Load(int3(int2(texelX.x, texelW.y), 0)), tex.Load(int3(texelW, 0)), f.x); // 再横向插值上排。
    return lerp(bottom, top, f.y); // 最后纵向插值。
}

// 天空盒图集的双线性取像素：与上一函数相同，但每个采样都夹在自己那一格里。
// 为什么需要夹紧：天空盒把六张面拼成 3×2 的大图，横跨格边取样会读到隔壁面的像素，
// 地平线附近就会出现一条颜色突变的接缝。`coord` 是零到一的图集坐标。
float4 ogxBilinearTextureSkybox(Sampler2D tex, float2 coord, float2 texSize)
{
    int2 grid = int2(floor(coord * float2(3.0, 2.0))); // 当前落在 3×2 图集的哪一格。
    int gridSize = int(floor(texSize.y * 0.5)); // 每格是正方形，边长取总高的一半。
    grid *= gridSize; // 格号换成格子的左上角纹素坐标。
    int4 border = int4(grid, grid + gridSize - 1); // 该格的闭区间边界，左下与右上。
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    float2 p = floor(coord); // 左下最近纹素。
    float2 f = coord - p; // 插值权重。
    int2 texelX = clamp(int2(p), border.xy, border.zw); // 左下纹素夹进本格。
    int2 texelW = clamp(texelX + int2(1), border.xy, border.zw); // 右上纹素同样夹紧。
    float4 bottom = lerp(tex.Load(int3(texelX, 0)), tex.Load(int3(int2(texelW.x, texelX.y), 0)), f.x); // 下排横向插值。
    float4 top = lerp(tex.Load(int3(int2(texelX.x, texelW.y), 0)), tex.Load(int3(texelW, 0)), f.x); // 上排横向插值。
    return lerp(bottom, top, f.y); // 纵向插值得到最终像素。
}

// 三次 B 样条的第零个权重；四个权重之和恒为一，单独取用才不会有亮度漂移。
// 为什么和库里已有的双三次采样不同：这里是一点五阶核，放大后更柔，参考包的天空贴图用它，
// 而 `ogxBicubicTexture` 用的是更锐的卡特穆尔-罗姆核；两条曲线不能互相替代。
// `a` 是采样点到纹素的小数偏移，取值零到一。
float ogxCubicWeight0(float a) { return (1.0 / 6.0) * (a * (a * (-a + 3.0) - 3.0) + 1.0); }

// 三次 B 样条的第二个权重：离采样点向右一个纹素。
float ogxCubicWeight1(float a) { return (1.0 / 6.0) * (a * a * (3.0 * a - 6.0) + 4.0); }

// 三次 B 样条的第三个权重：离采样点向右两个纹素。
float ogxCubicWeight2(float a) { return (1.0 / 6.0) * (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0); }

// 三次 B 样条的第四个权重：离采样点向右三个纹素，偏移越远权重越小。
float ogxCubicWeight3(float a) { return (1.0 / 6.0) * (a * a * a); }

// 左侧两个权重的和：把两次采样合并成一次双线性采样时用它做分母。
float ogxCubicWeightLow(float a) { return ogxCubicWeight0(a) + ogxCubicWeight1(a); }

// 右侧两个权重的和，与上一函数配对。
float ogxCubicWeightHigh(float a) { return ogxCubicWeight2(a) + ogxCubicWeight3(a); }

// 合并后左采样点在像素坐标里的位置：负一为左端，零为像素中心。
// 两个采样点不对称，必须按右权重占总权重的比例往左挪，画面才不会整体偏移半像素。
float ogxCubicOffsetLow(float a) { return -1.0 + ogxCubicWeight1(a) / (ogxCubicWeight0(a) + ogxCubicWeight1(a)); }

// 合并后右采样点的位置：正一为右端，按左权重占比往右挪。
float ogxCubicOffsetHigh(float a) { return 1.0 + ogxCubicWeight3(a) / (ogxCubicWeight2(a) + ogxCubicWeight3(a)); }

// 卡特穆尔-罗姆双三次采样：五次采样拼出十六像素的平滑放大，权重总和归一。
// 中间两个像素先合并成一次双线性采样，省掉四次纹理读取，画面与逐像素版本一致。
float3 ogxBicubicTexture(Sampler2D texSampler, float2 coord, float2 texSize)
{
    float2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize; // 换成像素坐标。
    float2 p = floor(coord - 0.5) + 0.5; // 左下最近像素中心。
    float2 f = coord - p; // 到该中心的小数偏移。
    float2 f2 = f * f; // 偏移平方。
    float2 f3 = f * f2; // 偏移立方。
    const float c = 0.5; // 卡特穆尔-罗姆张力。
    float2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 第一个像素权重。
    float2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 第二个像素权重。
    float2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 第三个像素权重。
    float2 w3 = c * f3 - c * f2; // 第四个像素权重。
    float2 w12 = w1 + w2; // 中间两个像素合并成一次双线性采样。
    float2 tc12 = texPixelSize * (p + w2 / w12); // 合并采样的位置。
    float2 tc0 = texPixelSize * (p - 1.0); // 最左或最下像素位置。
    float2 tc3 = texPixelSize * (p + 2.0); // 最右或最上像素位置。
    float4 color = float4(texSampler.SampleLevel(float2(tc12.x, tc0.y), 0.0).rgb, 1.0) * (w12.x * w0.y) +
                   float4(texSampler.SampleLevel(float2(tc0.x, tc12.y), 0.0).rgb, 1.0) * (w0.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc12.x, tc12.y), 0.0).rgb, 1.0) * (w12.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc3.x, tc12.y), 0.0).rgb, 1.0) * (w3.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc12.x, tc3.y), 0.0).rgb, 1.0) * (w12.x * w3.y); // 十字形五次采样，a 通道累计权重。
    return color.rgb / color.a; // 除以权重和，补偿省掉的四角。
}

// 十六像素三次模糊：四次双线性采样合成，专供六十四见方的噪声贴图。
float4 ogxBicubicBlurTexture(Sampler2D texSampler, float2 coord)
{
    const float texPixelSize = 1.0 / 64.0; // 噪声贴图一个像素的大小。
    coord = coord * 64.0 - 0.5; // 换成以像素中心为原点的坐标。
    float2 p = floor(coord); // 整数像素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 两个方向的前两个三次样条权重。
    float4 w1; // 两个方向的后两个三次样条权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
    w1.yw = ff * f; // 第四个权重是偏移立方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
    float4 s = w0 + w1; // 左右两对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= texPixelSize; // 换回零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return lerp(lerp(texSampler.SampleLevel(c.yw, 0.0), texSampler.SampleLevel(c.xw, 0.0), m.x),
                lerp(texSampler.SampleLevel(c.yz, 0.0), texSampler.SampleLevel(c.xz, 0.0), m.x), m.y); // 四次双线性采样得到十六像素的三次模糊。
}
