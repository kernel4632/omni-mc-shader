/*
生成文件：吸积盘模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库吸积盘模块：沿视线在黑洞附近步进，累加盘的颜色与透过率。
调用位置：任何需要画黑洞吸积盘的程序；Minecraft 光影由 `/omni-gfx/accretion.glsl` 引入，
    `rendering/world/end_disc.glsl` 的天空版与反射版只差参数，不再各写一份积分。
可复制示例：`vec4 d = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, seconds, 50, 3.0, 4, false, true);`
    返回 `rgb` 为盘颜色、`a` 为透过率。
设计原因与取舍：
    天空版与反射版只差步数、起点、噪声指数与是否叠星空；积分、空间扭曲与盘着色完全共用，所以放进通用库。
    星空仍由效果层叠加，因为那是末地天空的业务；本模块只依赖方向、噪声纹理与时间。
    写法与常数照 iterationT 原程序保留，包括圆环辉光、黑体色温与多普勒调制。
    方位角用库自己的 `ogxAtan2`，不再借用宿主的同名包装，保证模块可以单独编译。
*/
#ifndef OGX_ACCRETION_INCLUDED
#define OGX_ACCRETION_INCLUDED

// 数学提供黑体、旋转、径向轮廓与空间扭曲，雾模块提供分形噪声。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/fog.glsl"
// 吸积盘积分：`steps` 是步数，`startOffset` 是起始位置离黑洞的距离，
// `densityPower` 是噪声幂次（天空版四、反射版五），`detailAlongLongitude` 决定细节是否沿方位角分布，
// `doppler` 打开后按方位角调制亮度。返回 rgb 盘颜色与 a 透过率。
vec4 ogxAccretionDisc(vec3 rayDir, vec3 lightDir, float noise, sampler2D noiseTexture, float seconds,
    int steps, float startOffset, int densityPower, bool detailAlongLongitude, bool doppler)
{
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 吸积盘半径。
    const float discWidth = 3.5; // 吸积盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内半径。
    float rSteps = 1.0 / float(steps); // 步数倒数，最后做平均。
    vec3 eye = -lightDir * 8.0; // 视线起点。
    vec3 rayPos = eye + rayDir * startOffset; // 起始步进位置。
    mat3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 吸积盘的固定倾角。
    vec3 result = vec3(0.0); // 累积的盘颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少步进条纹。
    for (int i = 0; i < steps; i++) // 逐步前进。
    {
        if (transmittance < 0.0001) break; // 已被遮满就停止。
        ogxWarpSpace(rayDir, rayPos); // 靠近黑洞时光线被拉弯。
        rayPos += rayDir * stepLength; // 前进一步。
        vec3 discPos = rotation * rayPos; // 转到吸积盘坐标系。
        float r = length(discPos); // 到盘中心的半径。
        float p = ogxAtan2(-discPos.zx); // 盘面上的方位角。
        float h = discPos.y; // 离盘面的高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向衰减。
        float dist = abs(h); // 到盘面的距离。
        float discThickness = 0.1 * radialGradient; // 盘的厚度随半径变化。
        float fr = abs(r - discInner) + 0.4; // 到内边缘的距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 亮度衰减。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 靠近盘面的辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 只在盘厚范围内。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxRadialCurve(radialGradient); // 径向轮廓。
        float density = dr; // 当前密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 按离盘面距离衰减。
        density = ogxSaturate(density * 0.7); // 整体缩放。
        density = ogxSaturate(density + bloomFactor * 0.1); // 叠上辉光。
        if (density > 0.0001) // 有密度才算这一步的颜色。
        {
            vec3 discCoord; // 噪声采样坐标。
            vec3 shift; // 噪声随时间流动的方向。
            if (detailAlongLongitude) // 细节沿纬度分布时用方位角。
            {
                discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5;
                shift = seconds * vec3(0.1, 0.07, 0.0);
            }
            else // 默认细节只沿半径与高度分布。
            {
                discCoord = vec3(r, 0.0, h * 0.1) * 3.5;
                shift = seconds * vec3(0.03, 0.05, 0.0);
            }
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, 64.0); // 高质量云噪声。
            if (densityPower == 4) // 天空版：噪声四次方。
            {
                fbm = fbm * fbm;
                fbm = fbm * fbm;
                density *= fbm * dr;
            }
            else // 反射版：噪声五次方，写法与原程序一致。
            {
                float fbm2 = fbm * fbm;
                density *= fbm2 * fbm2 * fbm;
                density *= dr;
            }
            float gr = 1.0 - radialGradient; // 反径向。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮的辉光。
            vec3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应：一侧更亮。
            float stepTransmittance = exp2(-density * 7.0); // 这一步的透过率。
            float integral = 1.0 - stepTransmittance; // 这一步吸收掉的量。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 按透过率累加颜色。
        }
        vec2 t = vec2(1.0, 0.01); // 圆环截面参数。
        float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        vec3 ringColor = ogxBlackbody(12000.0); // 高色温的冷白。
        bloomDisc *= step(0.5, r); // 只在盘外缘以外。
        result += ringColor * bloomDisc * 0.1 * transmittance; // 叠上圆环辉光。
    }
    result *= rSteps; // 步数平均。
    return vec4(result, transmittance); // 交回盘颜色与剩余透过率。
}

#endif
