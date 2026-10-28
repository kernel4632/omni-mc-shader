#version 330 core
// 曝光统计：把几何画面的对数亮度压成两级小图，供后期换算曝光倍率。
// 调用位置：时间抗锯齿之后各画一次；天空不参与统计，亮云不会把地面压黑。
// 设计原因与取舍：自动曝光让同一套光照在不同太阳高度下都能看清暗部；
// 只统计几何像素，避免大面积明亮天空主导曝光。两次缩小都在显卡上完成，不回读 CPU。
#include "/omni-gfx/common/math.glsl"

uniform sampler2D uSource; // 来源颜色。
uniform sampler2D uDepth; // 深度，用来排除天空。
uniform vec2 uResolution; // 当前目标尺寸。
uniform int uMode; // 零是第一级，一是缩成一个像素。

out vec4 fragColor; // 红通道存平均对数亮度。

// 单像素对数亮度，夹在合理范围，极亮与极暗像素不会主导曝光。
float logLuminance(vec3 color) // 返回以二为底的对数。
{
    float luminance = max(ogxLuminance(color), 1e-4); // 避免对零取对数。
    return clamp(log2(luminance), -9.0, 5.0); // 约零点零零二到三十二。
}

void main() // 两级缩小共用同一个入口。
{
    if (uMode == 0) // 第一级：每个小像素取四个样本。
    {
        vec2 base = gl_FragCoord.xy / uResolution; // 小图上的位置，也是大块的中心。
        vec2 offset = 0.35 / uResolution; // 四个点落在大块内侧。
        vec2 uvs[4] = vec2[4](base + vec2(-offset.x, -offset.y), base + vec2(offset.x, -offset.y),
                              base + vec2(-offset.x, offset.y), base + vec2(offset.x, offset.y));
        float sum = 0.0; // 对数亮度和。
        float weight = 0.0; // 有效几何样本数。
        for (int i = 0; i < 4; i++) // 四个样本。
        {
            float depth = texture(uDepth, uvs[i]).r; // 深度。
            if (depth < 0.999) // 天空不参与。
            {
                sum += logLuminance(texture(uSource, uvs[i]).rgb); // 累加几何亮度。
                weight += 1.0; // 计数。
            }
        }
        fragColor = vec4(weight > 0.0 ? sum / weight : -99.0, 0.0, 0.0, 1.0); // 没有几何时写哨兵值。
    }
    else // 第二级：把上一级缩成一个像素。
    {
        float sum = 0.0; // 有效格子的和。
        float count = 0.0; // 有效格子数。
        for (int y = 0; y < 8; y++) // 八乘八。
        {
            for (int x = 0; x < 8; x++) // 八列。
            {
                float value = texture(uSource, (vec2(float(x), float(y)) + 0.5) / 8.0).r; // 上一级对数亮度。
                if (value > -20.0) // 跳过全天空格子。
                {
                    sum += value; // 累加。
                    count += 1.0; // 计数。
                }
            }
        }
        fragColor = vec4(count > 0.0 ? sum / count : -2.0, 0.0, 0.0, 1.0); // 平均对数亮度。
    }
}
