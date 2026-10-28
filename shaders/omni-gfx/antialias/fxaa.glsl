/*
生成文件：FXAA模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库抗锯齿 FXAA 模块：按亮度梯度找边缘方向，再沿边缘过滤。
调用位置：需要快速抗锯齿而不想接时间累积的程序；由 `/omni-gfx/antialias/fxaa.glsl` 引入。
可复制示例：
    vec3 sharp = ogxFxaa(color, texCoord, pixelSize, colorTexture); // 做一次边缘过滤。
设计原因与取舍：
    只读一帧颜色，不需要历史缓冲；四个邻域和两组内侧样本的顺序与参考实现相同。
当前状态：由 `shaders/effects/clarity/fxaa.glsl` 引入，`Fxaa` 直接调用 `ogxFxaa`。
*/
#ifndef OGX_ANTIALIAS_FXAA_INCLUDED
#define OGX_ANTIALIAS_FXAA_INCLUDED

// FXAA：按四邻域亮度梯度找边缘方向，再沿边缘取四个样本做抗锯齿。
vec3 ogxFxaa(vec3 rgbM, vec2 coord, vec2 pixelSize, sampler2D colorTexture)
{
    const float reduceMin = 1.0 / 64.0; // 最小梯度。
    const float reduceMul = 1.0 / 8.0; // 梯度缩放。
    const float spanMax = 16.0; // 最大搜索跨度。
    vec3 rgbNW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, -0.5), 0.0).xyz; // 左上。
    vec3 rgbNE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, -0.5), 0.0).xyz; // 右上。
    vec3 rgbSW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, 0.5), 0.0).xyz; // 左下。
    vec3 rgbSE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, 0.5), 0.0).xyz; // 右下。
    vec3 luma = vec3(0.299, 0.587, 0.114); // 亮度权重。
    float lumaNW = dot(rgbNW, luma); // 左上亮度。
    float lumaNE = dot(rgbNE, luma); // 右上亮度。
    float lumaSW = dot(rgbSW, luma); // 左下亮度。
    float lumaSE = dot(rgbSE, luma); // 右下亮度。
    float lumaM = dot(rgbM, luma); // 中心亮度。
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE))); // 最小亮度。
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE))); // 最大亮度。
    vec2 dir; // 边缘方向。
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * reduceMul), reduceMin); // 方向衰减。
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce); // 方向归一化。
    dir = min(vec2(spanMax, spanMax), max(vec2(-spanMax, -spanMax), dir * rcpDirMin)) * pixelSize; // 限制跨度并换成像素。
    vec3 rgbA = (1.0 / 2.0) * (textureLod(colorTexture, coord + dir * vec2(1.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(2.0 / 3.0 - 0.5), 0.0).xyz); // 内侧两点。
    vec3 rgbB = rgbA * (1.0 / 2.0) + (1.0 / 4.0) * (textureLod(colorTexture, coord + dir * vec2(0.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(3.0 / 3.0 - 0.5), 0.0).xyz); // 外侧两点。
    float lumaB = dot(rgbB, luma); // 外侧亮度。
    if ((lumaB < lumaMin) || (lumaB > lumaMax)) return rgbA; // 外侧落在亮度范围外就用内侧。
    return rgbB; // 否则用更宽的平均。
}

#endif
