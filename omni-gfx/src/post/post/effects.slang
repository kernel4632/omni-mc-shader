/*
后期子文件：相机动态模糊、曝光瓦片平均、镜头光斑与远景噪声。
调用位置：由 `post/post.slang` 内联，合成阶段的运动模糊与镜头效果调用这里。
可复制示例：`vec3 c = ogxMotionBlur(colorTex, coord, texel, pixel, velocity, 180.0, 8, true);`
设计原因与取舍：只处理整屏相机位移，没有实体速度缓冲；光斑形状与参考常数逐项一致。
*/
// 相机动态模糊：沿两帧之间的屏幕位移，在历史画面上取一串样本求平均。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理整屏位移。
float3 ogxMotionBlur(Sampler2D colorTexture, float2 coord, int2 texel, float2 pixel, float2 velocity,
    float shutterAngle, int quality, bool dither)
{
    if (length(velocity) < 5e-7) // 位移极小说明相机没动，直接取当前画面。
    {
        return ogxCurveToLinear3(colorTexture.Load(int3(texel, 0)).rgb);
    }
    float shutter = shutterAngle / 720.0; // 快门角换算成拖影长度。
    velocity = clamp(velocity * shutter, float2(-0.1), float2(0.1)); // 限制单帧拖影上限。
    float steps = float(quality); // 一侧的采样步数。
    float samples = 0.0; // 有效样本计数。
    float offset = 0.0; // 采样抖动。
    if (dither) // 交错梯度噪声打散条纹。
    {
        offset = ogxInterleavedGradientNoise(pixel);
    }
    float3 color = float3(0.0); // 输出颜色。
    for (float i = -steps; i <= steps; i++) // 沿快门方向对称取样。
    {
        float2 sampleCoord = coord + velocity / (steps + 1.0) * (i + offset); // 这个样本的坐标。
        if (ogxEqual(ogxSaturate(sampleCoord), sampleCoord)) // 坐标在画面内才采。
        {
            color += ogxCurveToLinear3(colorTexture.SampleLevel(sampleCoord, 0.0).rgb); // 累加历史颜色。
            samples++; // 计数。
        }
    }
    return color / samples; // 按有效样本数平均。
}

// 自动曝光分块统计的参数：屏幕尺寸、块大小、测光方式与亮度计权都由调用方给出。
// 字段名沿用光影侧写法，适配层因此只需要一次类型别名，不产生结构体拷贝。
struct OgxExposureParams
{
    float2 screen_size; // 画面像素尺寸。
    float2 pixel_size; // 一个像素在零到一坐标里的大小。
    int lod; // 多级纹理层级，决定一块覆盖多少像素。
    float luma_scale; // 管线亮度换算系数。
    float average; // 用一张粗样本估出的整体亮度，供亮度计权使用。
    int mode; // 测光方式：零默认、一中心权重、二只看中心、三全屏平均。
    int luminance_mode; // 亮度计权方式：零关闭，一到四对应四种曲线。
    float luminance_strength; // 亮度计权的强度。
    bool end_dimension; // 是否末地，末地默认测光不看中心。
    bool nether; // 是否下界，亮度计权在下界用固定指数。
    bool cave_mode; // 是否洞穴模式，洞穴按偏离整体亮度计权。
    bool overworld; // 是否主世界，亮度计权的指数范围与末地不同。
};

// 返回加权平均亮度，单位与输入画面一致；调用方再乘曝光输出系数并编码。
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
float ogxExposureTileAverage(Sampler2D sceneTexture, OgxExposureParams params)
{
    float tileScale = exp2(float(params.lod)); // 一个块覆盖多少像素。
    float2 tileCount = floor(params.screen_size / tileScale); // 每行每列有多少块。
    float2 tileCenter = tileCount * 0.5; // 块网格的中心。
    float exposure = 0.0; // 加权亮度累加。
    float weights = 0.0; // 权重累加。
    for (int x = 0; x < int(tileCount.x); x++) // 逐列遍历块。
    {
        for (int y = 0; y < int(tileCount.y); y++) // 逐行遍历块。
        {
            float tileExposure = ogxLuminance(ogxCurveToLinear3(sceneTexture.Load(int3(int2(x, y), params.lod)).rgb)) * params.luma_scale; // 这个块的亮度。
            float2 tileDistance = (tileCenter - float2(x, y) + 0.5) * params.pixel_size * tileScale * 2.0; // 块中心到画面中心的屏幕距离。
            float centerDistance = length(tileDistance); // 到画面中心的距离。
            float tileWeight = 1.0; // 块权重，先给等权。
            if (params.mode == 0) // 默认测光。
            {
                tileWeight = params.end_dimension ? 1.0 : ogxRemapSaturate(centerDistance, 0.6, 0.4); // 末地等权，其他维度越靠中心越高。
            }
            else if (params.mode == 1) // 中心权重较强。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.7, 0.0); // 中心权重曲线。
                tileWeight *= tileWeight; // 再平方，中心更突出。
            }
            else if (params.mode == 2) // 只看中心。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 与默认相同的曲线。
            }
            tileExposure = max(6.4e-9, tileExposure); // 避免全黑块把权重推到无穷。
            if (params.cave_mode && params.overworld) // 洞穴模式且在主世界时按偏离程度计权。
            {
                float caveWeight = params.average / tileExposure; // 相对整体亮度的比例。
                tileWeight *= pow(caveWeight, 0.7); // 越偏离整体亮度权重越大，适应洞穴。
            }
            else if (params.luminance_mode > 0) // 其他情况按亮度计权方式。
            {
                float lumaWeight = 1.0; // 相对亮度权重。
                if (params.luminance_mode == 1) // 预设一。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    if (params.nether) // 下界用固定指数。
                    {
                        lumaWeight = pow(lumaWeight, 0.7);
                    }
                    else if (params.overworld) // 主世界按整体亮度调指数。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.7); // 暗环境更偏向亮块。
                    }
                    else // 末地指数范围不同。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地曲线。
                    }
                }
                else if (params.luminance_mode == 2) // 预设二。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    lumaWeight = pow(lumaWeight, params.nether ? 0.7 : ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 下界固定，其余用较平的曲线。
                }
                else if (params.luminance_mode == 3) // 偏向暗部。
                {
                    lumaWeight = pow(params.average / tileExposure, params.luminance_strength); // 用选项给的强度。
                }
                else // 偏向高光。
                {
                    lumaWeight = pow(tileExposure / params.average, params.luminance_strength); // 比例取反。
                }
                tileWeight *= lumaWeight; // 把亮度权重乘进块权重。
            }
            exposure += tileExposure * tileWeight; // 累加加权亮度。
            weights += tileWeight; // 累加权重。
        }
    }
    return exposure / weights; // 加权平均。
}

// 镜头眩光：求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
// 先把偏移抬到三维再绕与中心垂直的轴旋转，最后取回二维，等价于绕画面中心弯折。
float2 ogxGlareDistOffset(float2 uv, float2 pxoffset, float barrel)
{
    float2 tocenter = uv.xy; // 当前点到中心的方向。
    float3 prep = normalize(float3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
    float angle = length(tocenter.xy) * 2.221 * barrel; // 旋转角随距离增大。
    float3 oldoffset = float3(pxoffset, 0.0); // 把偏移抬到三维。
    float3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 取回二维偏移。
}

// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点。
// 色散量同时改变三个通道的半径，蓝光偏得最多，边缘因此出现彩边。
float3 ogxGlareFlare(float2 uv, float2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxGlareDistOffset(uv, pos, barrel); // 先对鬼影位置做桶形畸变。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
    return float3(r, g, b); // 返回带色散的光点颜色。
}

// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
// 越靠后的光斑越小、越暗，模拟镜头内部多次反射的能量损失。
float3 ogxGlareOrb(float2 uv, float2 pos, float dist, float size, float barrel)
{
    float orbCount = 6.0; // 一组鬼影包含几个圆形光斑。
    float3 c = float3(0.0); // 累加结果。
    for (float i = 0.0; i < orbCount; i++) // 逐个光斑。
    {
        float j = i + 1.0; // 从一起数的序号。
        float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
        float colOffset = j / orbCount * 0.5; // 颜色偏移。
        float ss = size / (j + 1.0); // 越靠后的光斑越小。
        c += ogxGlareFlare(uv, pos, dist + offset, ss * 2.0, ss, barrel) * float3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
    }
    c += ogxGlareFlare(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 末尾再补一个大的柔和光斑。
    return c; // 返回光斑颜色。
}

// 画一个环状光环，三个通道同样做色散。
// 坐标先乘自身长度，圆点就被拉成环；分母里的二百五十控制环的锐度。
float3 ogxGlareRing(float2 uv, float2 pos, float dist, float chromaOffset, float blur)
{
    float2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿色通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
    return float3(r, g, b); // 返回光环颜色。
}

// 远景地形噪点：按楼层量化坐标，再按亮度与材质给一个可正可负的亮度扰动。
float3 ogxDistantNoise(float3 color, float3 pos, float materialIDs, int leafId, float steps, float strength)
{
    pos = floor(pos * steps) / steps; // 坐标量化到固定楼层，远景纹素不会闪烁。
    float weight = ogxLuminance(color) * 2.0 - 1.0; // 亮度映射到负一到一。
    weight = 1.0 - weight * weight; // 中间亮度权重最大。
    weight *= float(materialIDs == float(leafId)) + 1.0; // 树叶噪点更强。
    weight *= strength; // 整体强度。
    float noise = fract(sin(dot(pos.xy + fract(sin(pos.z * 91.3458) * 47453.5453), float2(12.9898, 78.233))) * 43758.5453); // 一维哈希。
    noise = (noise * 2.0 - 1.0) * weight; // 转成负一到一。
    return clamp(color - color * noise, 0.0, 1.0); // 按噪点压暗或提亮。
}
