/*
生成文件：抗锯齿模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库抗锯齿模块：YCoCg 颜色空间、历史邻域裁剪、三次采样与时间重投影。
调用位置：任何需要时间抗锯齿的程序；Minecraft 光影由 `/omni-gfx/antialias/antialias.glsl` 引入。
可复制示例：
    `vec3 y = ogxRgbToYCoCg(color);` 转到亮度与色差空间，亮度单独处理。
    `vec3 c = ogxClipAabb(avg, variance, history, true);` 把历史裁进当前邻域。
    `vec4 r = ogxTaaReproject(coord, velocity, depth, current, history, viewport, texel, projectionInverse, farPlane, jitter, 0.9, 1.0, 1e-4, false, false, true, false, false, referenceDepth);` 时间重投影。
设计原因与取舍：
    只做纯计算与显式采样，不读取历史画面或深度缓冲的全局名字；重投影的位移由调用方算好。
    YCoCg 让亮度与色差分开裁剪，避免高对比边缘出现彩边；算式与旧 `shaders/gfx/antialias.glsl` 一致。
    Slang 没有 GLSL 的按分量选择 `mix`，裁剪改成逐分量三元表达式，结果完全相同。
*/
#ifndef OGX_ANTIALIAS_INCLUDED
#define OGX_ANTIALIAS_INCLUDED

// 饱和、位打包与反余弦来自数学模块。
#include "/omni-gfx/math.glsl"
// 把线性颜色转到亮度与色差空间，亮度单独处理。
vec3 ogxRgbToYCoCg(vec3 color)
{
    return vec3(color.r * 0.25 + color.g * 0.5 + color.b * 0.25,
                  color.r * 0.5 - color.b * 0.5,
                  color.r * -0.25 + color.g * 0.5 + color.b * -0.25); // 亮度与两个色差。
}

// 从亮度与色差空间换回线性颜色。
vec3 ogxYCoCgToRgb(vec3 color)
{
    float y = color.x; // 亮度。
    float co = color.y; // 橙到青的色差。
    float cg = color.z; // 绿到品红的色差。
    return vec3(y + co - cg, y + cg, y - co - cg); // 逆变换。
}

// 把历史颜色裁进当前三乘三邻域；`toCenter` 为真时朝中心拉，否则按分量分别裁剪。
vec3 ogxClipAabb(vec3 average, vec3 variance, vec3 history, bool toCenter)
{
    if (toCenter) // 朝邻域中心方向拉回，边缘不会出现单通道色斑。
    {
        float eps = 1e-20; // 极小量，避免除零。
        vec3 extent = variance - eps; // 范围半径。
        vec3 offset = history - average; // 历史相对中心的偏移。
        vec3 unit = abs(offset / extent); // 各通道越界比例。
        float maxUnit = max(unit.x, max(unit.y, unit.z)); // 最大越界比例。
        return maxUnit > 1.0 ? average + offset / maxUnit : history; // 沿原方向拉回边界。
    }
    vec3 diff = history - average; // 历史相对中心的偏移。
    vec3 clipMax = vec3(diff.x > variance.x ? variance.x / diff.x : 1.0,
                            diff.y > variance.y ? variance.y / diff.y : 1.0,
                            diff.z > variance.z ? variance.z / diff.z : 1.0); // 超出上界的比例。
    vec3 clipMin = vec3(diff.x < -variance.x ? -variance.x / diff.x : 1.0,
                            diff.y < -variance.y ? -variance.y / diff.y : 1.0,
                            diff.z < -variance.z ? -variance.z / diff.z : 1.0); // 超出下界的比例。
    diff *= clipMax.x * clipMax.y * clipMax.z * clipMin.x * clipMin.y * clipMin.z; // 一次缩到范围内。
    return average + diff; // 返回裁剪后的历史。
}

// 参考包的三参数版本：默认不朝中心拉，逐分量裁剪；旧调用点不需要传开关。
vec3 ogxClipAabb(vec3 average, vec3 variance, vec3 history)
{
    return ogxClipAabb(average, variance, history, false);
}

// 三次采样的五个支撑点：中心行列各取一次，比双线性更锐，代价是五次取样。
// `coord` 与 `texSize` 都是零到一坐标口径，返回四分量，透明度原样带回。
vec4 ogxBicubicTexture4(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个纹素的大小。
    coord = coord * texSize; // 换到像素坐标。
    vec2 p = floor(coord - 0.5) + 0.5; // 采样核中心。
    vec2 f = coord - p; // 中心偏移。
    vec2 f2 = f * f; // 平方。
    vec2 f3 = f * f2; // 立方。
    float c = 0.5; // 三次核系数。
    vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 最左权重。
    vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 左权重。
    vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 右权重。
    vec2 w3 = c * f3 - c * f2; // 最右权重。
    vec2 w12 = w1 + w2; // 左右权重和。
    vec2 tc12 = texel * (p + w2 / w12); // 中间采样坐标。
    vec2 tc0 = texel * (p - 1.0); // 最左采样点。
    vec2 tc3 = texel * (p + 2.0); // 最右采样点。
    vec4 color = textureLod(source, vec2(tc12.x, tc0.y), 0.0) * (w12.x * w0.y)
                 + textureLod(source, vec2(tc0.x, tc12.y), 0.0) * (w0.x * w12.y)
                 + textureLod(source, tc12, 0.0) * (w12.x * w12.y)
                 + textureLod(source, vec2(tc3.x, tc12.y), 0.0) * (w3.x * w12.y)
                 + textureLod(source, vec2(tc12.x, tc3.y), 0.0) * (w12.x * w3.y); // 五个采样点加权。
    return color / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y); // 归一化。
}

// 屏幕深度换米制距离；时间抗锯齿的深度比较与参考深度都用这一套。
float ogxTaaLinearDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度，写历史参考深度时用。
float ogxTaaScreenDepth(float depth, mat4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 读当前帧颜色；`packedDepth` 为真时透明度是屏幕深度，读完换成米制，供下界历史使用。
vec4 ogxTaaSampleCurrent(sampler2D colorTexture, vec2 coord, vec2 viewport, mat4 projectionInverse, bool packedDepth, bool bicubic)
{
    vec4 data; // 先取颜色；分支写成块，严格对照才能按布尔参数裁掉未选中的采样。
    if (bicubic) { data = ogxBicubicTexture4(colorTexture, coord, viewport); }
    else { data = textureLod(colorTexture, coord, 0.0); }
    if (packedDepth) // 下界把颜色与深度放在同一张图。
    {
        data.rgb = ogxRgbToYCoCg(data.rgb); // 颜色转亮度色差空间。
        data.a = ogxTaaLinearDepth(data.a, projectionInverse); // 深度换米制。
        return data; // 交回四分量。
    }
    return vec4(ogxRgbToYCoCg(data.rgb), 0.0); // 深度占位为零。
}

// 精确读当前帧纹素；邻域方差统计用，整数坐标不会混入邻居颜色。
vec4 ogxTaaFetchCurrent(sampler2D colorTexture, ivec2 coord, mat4 projectionInverse, bool packedDepth)
{
    vec4 data = texelFetch(colorTexture, coord, 0); // 精确读取。
    if (packedDepth) // 下界连深度一起读。
    {
        data.rgb = ogxRgbToYCoCg(data.rgb); // 颜色转亮度色差空间。
        data.a = ogxTaaLinearDepth(data.a, projectionInverse); // 深度换米制。
        return data; // 四分量带深度。
    }
    return vec4(ogxRgbToYCoCg(data.rgb), 0.0); // 主世界与末地只要颜色。
}

// 双线性读历史里打包的两个参考深度，返回两个分量的双线性插值。
vec2 ogxTaaPrevDepthBilinear(sampler2D historyTexture, vec2 coord, vec2 viewport)
{
    coord = coord * viewport - 0.5; // 换到纹素坐标并移到纹素中心。
    vec2 f = fract(coord); // 纹素内小数偏移。
    ivec2 texel = ivec2(coord); // 左上角纹素。
    vec2 s0 = ogxUnpack2x16(texelFetch(historyTexture, texel, 0).a); // 左上角两个参考深度。
    vec2 s1 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(1, 0), 0).a); // 右上角。
    vec2 s2 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(0, 1), 0).a); // 左下角。
    vec2 s3 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(1, 1), 0).a); // 右下角。
    return mix(mix(s0, s1, f.x), mix(s2, s3, f.x), f.y); // 双向插值。
}

// 读上一帧历史颜色与参考深度；`packedDepth` 为真时从透明度解包参考深度。
vec4 ogxTaaSamplePrevious(sampler2D historyTexture, vec2 coord, vec2 viewport, mat4 projectionInverse, bool packedDepth, bool bicubic)
{
    vec4 data; // 先取历史颜色；分支写成块，严格对照才能按布尔参数裁掉未选中的采样。
    if (bicubic) { data = ogxBicubicTexture4(historyTexture, coord, viewport); }
    else { data = textureLod(historyTexture, coord, 0.0); }
    if (packedDepth) // 下界历史带参考深度。
    {
        float prevDepth = ogxTaaPrevDepthBilinear(historyTexture, coord, viewport).x; // 解包上一帧参考深度。
        return vec4(ogxRgbToYCoCg(data.rgb), ogxTaaLinearDepth(prevDepth, projectionInverse)); // 颜色与米制参考深度。
    }
    return vec4(ogxRgbToYCoCg(data.rgb), 0.0); // 参考深度占位。
}

// 读上一帧某个纹素的参考深度；普通维度存在透明度，下界从打包值里取第二个分量。
float ogxTaaPrevDepthFetch(sampler2D historyTexture, ivec2 coord, bool packedDepth)
{
    if (packedDepth) { return ogxUnpack2x16(texelFetch(historyTexture, coord, 0).a).y; } // 下界从打包值取第二个分量。
    return texelFetch(historyTexture, coord, 0).w; // 主世界直接读透明度通道。
}

// 取上一帧三乘三邻域的参考深度最小与最大值，供深度一致性判断。
vec2 ogxTaaPrevDepthMinmax(sampler2D historyTexture, vec2 prevCoord, vec2 viewport, bool packedDepth)
{
    ivec2 nearest = ivec2(prevCoord * viewport); // 上一帧坐标换成最近纹素。
    float d0 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, -1), packedDepth); // 左上。
    float d1 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, -1), packedDepth); // 上方。
    float d2 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, -1), packedDepth); // 右上。
    float d3 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, 0), packedDepth); // 左侧。
    float d4 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, 0), packedDepth); // 中心。
    float d5 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, 0), packedDepth); // 右侧。
    float d6 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, 1), packedDepth); // 左下。
    float d7 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, 1), packedDepth); // 下方。
    float d8 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, 1), packedDepth); // 右下。
    float minDepth = min(d0, min(d1, min(d2, min(d3, min(d4, min(d5, min(d6, min(d7, d8)))))))); // 九点最小值。
    float maxDepth = max(d0, max(d1, max(d2, max(d3, max(d4, max(d5, max(d6, max(d7, d8)))))))); // 九点最大值。
    return vec2(minDepth, maxDepth); // 返回范围。
}

// 当前帧三乘三邻域：求颜色均值、十字均值、方差范围；`packedDepth` 为真时同时给出参考深度范围。
vec3 ogxTaaVariance3x3(ivec2 coord, vec3 currColor, sampler2D colorTexture, mat4 projectionInverse, bool packedDepth,
    float aggression, out vec3 avgColor, out vec3 crossAvg, out vec2 referenceMinmax)
{
    vec4 data0 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, -1), projectionInverse, packedDepth); // 左上。
    vec4 data1 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, -1), projectionInverse, packedDepth); // 上方。
    vec4 data2 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, -1), projectionInverse, packedDepth); // 右上。
    vec4 data3 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, 0), projectionInverse, packedDepth); // 左侧。
    vec4 data4 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, 0), projectionInverse, packedDepth); // 中心。
    vec4 data5 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, 0), projectionInverse, packedDepth); // 右侧。
    vec4 data6 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, 1), projectionInverse, packedDepth); // 左下。
    vec4 data7 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, 1), projectionInverse, packedDepth); // 下方。
    vec4 data8 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, 1), projectionInverse, packedDepth); // 右下。
    crossAvg = data1.rgb + data3.rgb + data4.rgb + data5.rgb + data7.rgb; // 十字五点之和。
    avgColor = (crossAvg + data0.rgb + data2.rgb + data6.rgb + data8.rgb) / 9.0; // 九点均值。
    crossAvg *= 0.2; // 十字均值。
    vec3 m2 = (data0.rgb * data0.rgb + data1.rgb * data1.rgb + data2.rgb * data2.rgb + data3.rgb * data3.rgb + data4.rgb * data4.rgb
        + data5.rgb * data5.rgb + data6.rgb * data6.rgb + data7.rgb * data7.rgb + data8.rgb * data8.rgb) / 9.0; // 二阶矩。
    vec3 variance = sqrt(m2 - avgColor * avgColor) * aggression; // 标准差乘裁剪强度得到范围半径。
    vec3 minColor = min(avgColor - variance, currColor) * 0.5; // 范围下界，至少包住当前颜色。
    vec3 maxColor = max(avgColor + variance, currColor) * 0.5; // 范围上界。
    if (packedDepth) // 下界还要邻域参考深度范围。
    {
        referenceMinmax = vec2(min(data0.a, min(data1.a, min(data2.a, min(data3.a, min(data4.a, min(data5.a, min(data6.a, min(data7.a, data8.a)))))))),
            max(data0.a, max(data1.a, max(data2.a, max(data3.a, max(data4.a, max(data5.a, max(data6.a, max(data7.a, data8.a))))))))); // 九点深度范围。
    }
    else // 普通维度没有参考深度。
    {
        referenceMinmax = vec2(0.0); // 占位。
    }
    avgColor = minColor + maxColor; // 输出范围中心。
    return maxColor - minColor; // 输出范围半径。
}

// 时间重投影：当前帧与历史帧按邻域范围、运动量、深度一致性混合；返回颜色与代表深度。
// `packedDepth` 为真时按上下界打包参考深度，`referenceDepth` 回传换回屏幕深度的参考值。
vec4 ogxTaaReproject(vec2 coord, vec3 velocity, float currDepthMin, sampler2D currentTexture, sampler2D historyTexture,
    vec2 viewport, ivec2 texelCoord, mat4 projectionInverse, float farPlane, vec2 jitter,
    float blendWeight, float aggression, float depthThreshold, bool bicubicCurrent, bool bicubicPrevious,
    bool clipToCenter, bool depthCompare, bool microBlur, bool packedDepth, out float referenceDepth)
{
    vec2 unjitter = coord + jitter * 0.5; // 撤销本帧抖动，取样才落在真实位置。
    vec4 currData = ogxTaaSampleCurrent(currentTexture, unjitter, viewport, projectionInverse, packedDepth, bicubicCurrent); // 当前帧样本。
    vec3 currColor = currData.rgb; // 当前帧颜色。
    vec3 avgColor = currColor; // 邻域均值初值。
    vec3 crossAvg = currColor; // 十字均值初值。
    vec2 referenceMinmax = vec2(0.0); // 参考深度范围初值。
    vec3 variance = ogxTaaVariance3x3(texelCoord, currColor, currentTexture, projectionInverse, packedDepth, aggression, avgColor, crossAvg, referenceMinmax); // 求邻域范围。
    vec2 prevCoord = coord - velocity.xy; // 退回上一帧位置。
    vec4 prevData = ogxTaaSamplePrevious(historyTexture, prevCoord, viewport, projectionInverse, packedDepth, bicubicPrevious); // 读上一帧历史。
    vec3 prevColor = ogxClipAabb(avgColor, variance, prevData.rgb, clipToCenter); // 把历史夹进当前范围。
    if (packedDepth) // 下界把参考深度夹到邻域范围。
    {
        float depthTolerance = 2e-5; // 参考深度容差，极小，避免抖出条纹。
        prevData.a = clamp(prevData.a + velocity.z, referenceMinmax.x - depthTolerance, referenceMinmax.y + depthTolerance); // 夹到邻域深度范围。
    }
    float blend = blendWeight; // 历史基础权重。
    vec2 pixelVelocity = abs(fract(velocity.xy * viewport) - 0.5) * 2.0; // 像素为单位的运动量。
    blend *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75; // 运动越大历史权重越低。
    blend *= float(ogxEqual(ogxSaturate(coord), coord)); // 上一帧坐标出屏时不用历史。
    if (depthCompare) // 深度比较通过才保留历史权重。
    {
        vec2 prevDepth = ogxTaaPrevDepthMinmax(historyTexture, prevCoord, viewport, packedDepth); // 上一帧深度范围。
        float currDist = ogxTaaLinearDepth(currDepthMin, projectionInverse); // 当前帧换成米制。
        float threshold = max(depthThreshold - currDist / farPlane * 0.2 * depthThreshold, 1e-5); // 越远阈值越小。
        blend *= step(prevDepth.x - currDepthMin + velocity.z, threshold); // 历史更深一侧的一致性判断。
        blend *= step(currDepthMin - velocity.z - prevDepth.y, threshold); // 历史更浅一侧的一致性判断。
    }
    if (microBlur) // 权重低时更倾向十字均值，抑制闪烁。
    {
        currColor = mix(crossAvg, currColor, ogxSaturate(blend * 5.0 - 0.5));
    }
    currColor = mix(currColor, prevColor, blend); // 按权重把历史混进当前帧。
    if (packedDepth) // 下界参考深度也按权重混合。
    {
        referenceDepth = mix(currData.a, prevData.a, blend); // 混合参考深度。
        referenceDepth = ogxTaaScreenDepth(referenceDepth, projectionInverse); // 换回屏幕深度再打包。
    }
    else // 普通维度不需要参考深度。
    {
        referenceDepth = 0.0; // 占位。
    }
    return vec4(ogxYCoCgToRgb(currColor), currDepthMin); // 返回颜色与代表深度。
}

// iterationT 的远景单点深度：参考签名不带纹理，库把深度图作为显式资源。
float ogxSampleDepthDhFetch(ivec2 coord, sampler2D depthTexture)
{
    return texelFetch(depthTexture, coord, 0).x; // 精确读一个像素。
}

// iterationT 的远景最近三乘三深度：九个像素取最小值，避免细缝把背景深度拉远。
float ogxSampleCurrDepthDhFetchClosest3x3(ivec2 coord, sampler2D depthTexture)
{
    float d0 = ogxSampleDepthDhFetch(coord + ivec2(-1, -1), depthTexture); // 左上。
    float d1 = ogxSampleDepthDhFetch(coord + ivec2(0, -1), depthTexture); // 上。
    float d2 = ogxSampleDepthDhFetch(coord + ivec2(1, -1), depthTexture); // 右上。
    float d3 = ogxSampleDepthDhFetch(coord + ivec2(-1, 0), depthTexture); // 左。
    float d4 = ogxSampleDepthDhFetch(coord + ivec2(0, 0), depthTexture); // 中。
    float d5 = ogxSampleDepthDhFetch(coord + ivec2(1, 0), depthTexture); // 右。
    float d6 = ogxSampleDepthDhFetch(coord + ivec2(-1, 1), depthTexture); // 左下。
    float d7 = ogxSampleDepthDhFetch(coord + ivec2(0, 1), depthTexture); // 下。
    float d8 = ogxSampleDepthDhFetch(coord + ivec2(1, 1), depthTexture); // 右下。
    return min(d0, min(d1, min(d2, min(d3, min(d4, min(d5, min(d6, min(d7, d8)))))))); // 九点最小。
}

// iterationT 时间重投影：当前帧颜色、三乘三方差、历史颜色与历史深度按参考顺序混合。
// 为什么单独一份：合并版 `ogxTaaReproject` 还带下界打包、微模糊等扩展，默认路径的
// 采样顺序与参考不同；严格对照需要一条只走主世界参考分支的入口。
vec4 ogxTaaTemporalBlend(vec2 coord, vec3 velocity, float currDepthMin,
    sampler2D currentTexture, sampler2D historyTexture, vec2 viewport, ivec2 texelCoord,
    mat4 projectionInverse, float farPlane, vec2 jitter, float blendWeight,
    float aggression, float depthThreshold, bool bicubicPrevious)
{
    vec2 unjitterCoord = coord + jitter * 0.5; // 撤销本帧抖动，取样回到真实位置。
    vec4 currData = ogxTaaSampleCurrent(currentTexture, unjitterCoord, viewport, projectionInverse, false, false); // 当前帧颜色，转亮度色差。
    vec3 currColor = currData.rgb; // 当前帧颜色。
    vec3 avgColor = currColor; // 邻域均值占位。
    vec3 crossAvgColor = currColor; // 十字均值占位。
    vec2 referenceMinmax = vec2(0.0); // 主世界不用参考深度范围。
    vec3 variance = ogxTaaVariance3x3(texelCoord, currColor, currentTexture, projectionInverse, false,
        aggression, avgColor, crossAvgColor, referenceMinmax); // 九邻域方差与两个均值。
    vec2 prevCoord = coord - velocity.xy; // 退回上一帧屏幕位置。
    vec3 prevColor = ogxTaaSamplePrevious(historyTexture, prevCoord, viewport, projectionInverse,
        false, bicubicPrevious).rgb; // 上一帧历史颜色。
    prevColor = ogxClipAabb(avgColor, variance, prevColor); // 把历史裁进当前邻域。
    float blend = blendWeight; // 历史混合权重。
    vec2 pixelVelocity = abs(fract(velocity.xy * viewport) - 0.5) * 2.0; // 以像素为单位的运动量。
    blend *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75; // 运动越大越信当前帧。
    blend *= float(ogxEqual(ogxSaturate(coord), coord)); // 出屏坐标不混历史。
    vec2 prevDepth = ogxTaaPrevDepthMinmax(historyTexture, prevCoord, viewport, false); // 上一帧九邻域参考深度。
    float currDist = ogxTaaLinearDepth(currDepthMin, projectionInverse); // 当前深度换成米制。
    float threshold = max(depthThreshold - currDist / farPlane * 0.2 * depthThreshold, 1e-5); // 越远阈值越小。
    blend *= step(prevDepth.x - currDepthMin + velocity.z, threshold); // 历史更深一侧的一致性。
    blend *= step(currDepthMin - velocity.z - prevDepth.y, threshold); // 历史更浅一侧的一致性。
    currColor = mix(crossAvgColor, currColor, ogxSaturate(blend * 5.0 - 0.5)); // 低权重时更靠十字均值。
    currColor = mix(currColor, prevColor, blend); // 按权重混入历史。
    currColor = ogxYCoCgToRgb(currColor); // 回到 RGB。
    return vec4(currColor, currDepthMin); // 带回代表深度。
}

float ogxTaaSampleDepthFetch(sampler2D depthTexture, ivec2 coord)
{
    return texelFetch(depthTexture, coord, 0).x; // 当前像素的深度。
}

#endif
