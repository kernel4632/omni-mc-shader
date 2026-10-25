#version 330 core
// 曝光统计阶段：把整幅画面压成两级的平均对数亮度，供后期换算曝光倍率。
// 调用位置：水面合成之后、后期之前各绘制一次，第一次缩到六十四乘三十六，第二次缩到一个像素。
// 设计原因与取舍：用对数亮度而不是算术平均，亮部不会因为一片太阳高光把整幅压暗；
// 每级只取固定数量的样本，成本可以忽略，也不需要把像素读回 CPU，避免显卡等待。
#include "/omni-gfx/math.glsl"

uniform sampler2D uSource; // 来源纹理，第一级是全分辨率颜色，第二级是上一级的小图。
uniform sampler2D uDepth; // 场景深度，第一级用它排除天空，避免亮天空压暗地面。
uniform vec2 uResolution; // 当前渲染目标的尺寸。
uniform int uMode; // 零表示第一级取平均，一表示把上一级缩成一个像素。

out vec4 fragColor; // 红色通道存平均对数亮度。

// 单个像素的对数亮度：夹在很小的范围内，极暗和极亮的个别像素不会主导曝光。
float logLuminance(vec3 color)
{
    float luminance = max(ogxLuminance(color), 1e-4); // 避免对零取对数。
    return clamp(log2(luminance), -9.0, 5.0); // 约零点零零二到三十二之间。
}

void main()
{
    if (uMode == 0) // 第一级：每个小图像素覆盖来源画面的一大块，取四个点估计。
    {
        vec2 base = gl_FragCoord.xy / uResolution; // 当前小图像素在画面里的相对位置。
        vec2 offset = 0.35 / uResolution; // 四个点落在这一块的内侧。
        vec2 uvs[4] = vec2[4](base + vec2(-offset.x, -offset.y), base + vec2(offset.x, -offset.y),
                              base + vec2(-offset.x, offset.y), base + vec2(offset.x, offset.y));
        float sum = 0.0; // 几何像素的对数亮度之和。
        float weight = 0.0; // 几何像素数量。
        for (int i = 0; i < 4; i++)
        {
            float depth = texture(uDepth, uvs[i]).r;
            if (depth < 0.999) // 天空不参与曝光统计，亮云不会把草坡压黑。
            {
                sum += logLuminance(texture(uSource, uvs[i]).rgb);
                weight += 1.0;
            }
        }
        fragColor = vec4(weight > 0.0 ? sum / weight : -99.0, 0.0, 0.0, 1.0);
    }
    else // 第二级：把六十四乘三十六的小图缩成一个像素。
    {
        float sum = 0.0; // 几何样本的和。
        float count = 0.0;
        for (int y = 0; y < 8; y++) // 八乘八共六十四个样本。
        {
            for (int x = 0; x < 8; x++)
            {
                vec2 uv = (vec2(float(x), float(y)) + 0.5) / 8.0; // 均匀铺满上一级小图。
                float value = texture(uSource, uv).r; // 上一级已经是对数亮度。
                if (value > -20.0) // 跳过全天空的格子。
                {
                    sum += value;
                    count += 1.0;
                }
            }
        }
        fragColor = vec4(count > 0.0 ? sum / count : -2.0, 0.0, 0.0, 1.0); // 整幅几何画面的平均对数亮度。
    }
}
