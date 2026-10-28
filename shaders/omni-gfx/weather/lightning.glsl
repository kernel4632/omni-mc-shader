/*
生成文件：闪电模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库闪电模块：闪电照亮表面、体积云与雾，末地光源位置与颜色。
调用位置：雷暴天气的表面、云与雾程序；由 `/omni-gfx/weather/lightning.glsl` 引入。
可复制示例：
    vec3 cloud = ogxLightningFlash(feetPos, boltPosition, normal, effect, phase); // 表面闪电。
    vec3 color = ogxLightningCloud(feetPos, boltPosition, effect); // 云层闪电。
设计原因与取舍：
    参考实现直接读 `lightningBoltPosition` 与末地宏。库把闪电位置、强度、光色和随机纹理显式传入，
    距离衰减、次表面相位与末地光柱混合的常数和分支保持参考实现。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。闪电目前只被库内反射模块间接引用，没有独立画面入口。
*/
#ifndef OGX_WEATHER_LIGHTNING_INCLUDED
#define OGX_WEATHER_LIGHTNING_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 闪电照亮表面：距离衰减、次表面相位与法线朝向一起决定亮度。
vec3 ogxLightningFlash(vec3 feetPlayerPos, vec4 boltPosition, vec3 worldNormal, vec3 lightningEffect,
    inout float phase)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y + 16.0, boltPosition.y + 116.0), boltPosition.z); // 闪电到表面。
    float lightDistance = 300.0; // 照明半径。
    float lightningLight = max(1.0 - length(lightningPos) / lightDistance, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    vec3 phasePos = normalize(feetPlayerPos) + vec3(boltPosition.x, boltPosition.y + 60.0, boltPosition.z); // 相位方向。
    float phaseOrigin = 1.0 - ogxSaturate(dot(normalize(feetPlayerPos), normalize(phasePos))); // 相位夹角。
    phase = exp(sqrt(phaseOrigin) * -2.0) * 5.0 * lightningLight; // 次表面相位。
    float ndotl = ogxSaturate(dot(lightningPos, -worldNormal)); // 法线朝向。
    return lightningEffect * lightningLight * ndotl; // 最终闪电。
}

// Eclipse 闪电照亮表面入口：参考签名的第二个位置参数不使用，真实位置来自 vec4 闪电缓冲。
// 为什么保留这个空参数：外部调用点按参考签名传参，库只把真实位置显式接进来。
vec3 ogxLightningFlashReference(vec3 feetPlayerPos, vec3 lightningBoltPos, vec3 worldNormal,
    inout float phase, vec4 boltPosition, vec3 lightningEffect)
{
    return ogxLightningFlash(feetPlayerPos, boltPosition, worldNormal, lightningEffect, phase);
}

// 闪电照亮体积云：只按距离衰减。
vec3 ogxLightningCloud(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 400.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 闪电照亮体积雾：只在闪电强度大于一时生效。
vec3 ogxLightningFog(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0 || boltPosition.w < 1.0) return vec3(0.0); // 弱闪电不照雾。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 150.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -15.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 末地光源位置：闪电位置吸到两百格网格，再按体积权重混向中心光柱。
vec3 ogxLightSourcePosition(vec3 worldPos, vec3 cameraPos, float vortexBounds, vec3 manualLightPos,
    vec3 randomOffset, bool theOrb)
{
    vec3 vortexPos = worldPos - vec3(0.0, 200.0, 0.0); // 中心光柱。
    vec3 lightningPos = worldPos - cameraPos - manualLightPos; // 闪电光。
    float cellSize = 200.0; // 网格大小。
    lightningPos += fract(cameraPos / cellSize) * cellSize - cellSize * 0.5; // 吸到网格。
    lightningPos -= randomOffset * 2.5; // 随机偏移。
    if (theOrb) return lightningPos; // 宝珠模式只看闪电位置。
    return mix(lightningPos, vortexPos, vortexBounds); // 按体积混合。
}

// iterationT 末地光源位置入口：先从第四张缓冲的固定像素取随机偏移，再调用主公式。
// 为什么单独一层：参考函数内部直接读 `colortex4`，主公式把随机偏移当参数；
// 严格对照需要把这次取像素放回函数体。
vec3 ogxLightSourcePositionReference(vec3 worldPos, vec3 cameraPos, float vortexBounds,
    sampler2D randomTexture, ivec2 randomTexel, vec3 manualLightPos, bool theOrb)
{
    vec3 randomOffset = (texelFetch(randomTexture, randomTexel, 0).xyz / 150.0) * 2.0 - 1.0; // 参考实现的随机偏移。
    return ogxLightSourcePosition(worldPos, cameraPos, vortexBounds, manualLightPos,
        randomOffset, theOrb); // 主公式原样转发。
}

// 末地光源颜色：闪电色与光柱色按体积权重混合。
vec3 ogxLightSourceColors(float vortexBounds, float lightningflash, vec3 vortexColor, vec3 lightningColor,
    vec3 orbColor, float orbMult, bool theOrb)
{
    vec3 lightning = lightningColor * lightningflash; // 闪电色按强度缩放。
    if (theOrb) return orbColor * orbMult; // 宝珠模式。
    return mix(lightning, vortexColor, vortexBounds); // 按体积混合。
}

#endif
