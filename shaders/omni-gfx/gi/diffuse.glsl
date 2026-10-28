/*
生成文件：漫反射光照模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库方块光模块：光照图曲线、LPV 体积混合与体素版方块光。
调用位置：需要复现 Eclipse `diffuse_lighting.glsl` 的程序；Minecraft 光影由
    `/omni-gfx/gi/diffuse.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    `vec3 light = ogxBlockLightLighting(lightColor, lightmap, lpvSample, handLight, lpvPos, 32.0, 4.0, 1.0, true, true);`
设计原因与取舍：
    参考实现直接读 `lightmap`、LPV 图与手光颜色。库把这些输入全部改成显式参数；
    分支、常数和采样顺序保持参考实现。
    手持光、手电与手光阴影统一放在 `heldlight.slang`，本文件只负责方块光合成，
    避免同一个手光主体分成两个模块。
当前状态：由 `gi/gi` 引入并编译；宿主 `doBlockLightLighting` 调用 `ogxBlockLightLightingVoxelExact`。
*/
#ifndef OGX_GI_DIFFUSE_INCLUDED
#define OGX_GI_DIFFUSE_INCLUDED

// 方块光合成：原版光照图曲线、LPV 体积、手持光与手电阴影一起决定最终方块光。
// `lpvSample` 与 `handLight` 由调用方先算好，库只负责曲线与混合。
vec3 ogxBlockLightLighting(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount,
    bool vanillaMask, bool useLpv)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float brightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    brightspot *= brightspot * brightspot; // 三次方。
    float lightCurve = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightCurve *= lightCurve;
    float lightmapCurve = mix(lightCurve, 2.5, brightspot); // 混合曲线。
    vec3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (useLpv) // 有 LPV 时才混合体积。
    {
        if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版遮罩。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
        float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        falloff = 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0); // 参考实现曲线。
        blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), falloff); // 体积外回退。
        blockLight += handLight; // 手持光相加。
    }
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}


// 方块光体素版：LPV 采样与手持光由调用方传入，曲线和边缘淡出与参考实现相同。
vec3 ogxBlockLightLightingVoxel(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightmapLight *= lightmapLight;
    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot); // 混合曲线。
    vec3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版光照图遮罩。
    vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
    float voxelRangeFalloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
    voxelRangeFalloff = 1.0 - pow(1.0 - pow(voxelRangeFalloff, 1.5), 3.0); // 参考实现的曲线。
    blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), voxelRangeFalloff); // 体积外回退。
    blockLight += handLight; // 手持光直接相加。
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 参考签名版的方块光体素曲线：只保留 `specular.glsl` 默认分支里的光照图曲线。
// 为什么单独一份：增强版还会混入 LPV 与手持光，默认路径的常数集合会多出参考没有的值；
// 严格对照需要一个只做参考算式的入口，调用方按需选择增强版或这一份。
vec3 ogxBlockLightLightingVoxelExact(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, float torchAmount)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 参考实现先把光照图夹到合法范围。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区线性起点。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方让高亮区收窄。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 平方根曲线。
    lightmapLight *= lightmapLight; // 再平方，暗部抬升更明显。
    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot); // 高亮区混向固定亮度。
    vec3 blockLight = lightmapCurve * lightColor; // 光照图乘方块光颜色。
    return blockLight * torchAmount; // 参考实现最后乘火把亮度。
}

#endif
