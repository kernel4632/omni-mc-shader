/*
Omni 通用图形库雾模块：高度衰减、噪声雾团、粉末效应、混合相位与沿视线积分。
调用位置：地形、水面与低空空气的雾；Minecraft 光影由 `/omni-gfx/fog/fog.glsl` 引入。
可复制示例：
    OgxFog f = ogxFogDefault(); // 取默认雾。
    float4 r = ogxFogMarch(f, camKm, worldKm, sunDir, sunColor, j, 10); // 沿视线积分雾。
    c = ogxFogApply(c, r); // 把雾合成到颜色。
设计原因与取舍：
    密度剖面与相位来自旧 `shaders/gfx/fog.glsl` 的 `gfx_fog_density_height`、`gfx_fog_density_noise`
    与 `gfx_fog_phase`，把纹理噪声换成程序化值噪声，保持雾团边缘与高度衰减的手感。
    步数与抖动由调用方给出，库不读取天气、选项或宿主时间；返回预乘散射色与剩余透过率，
    调用方按自己的混合顺序合成，避免和大气散射重复叠加。
*/
#ifndef OGX_FOG_INCLUDED
#define OGX_FOG_INCLUDED

// 数学提供相函数，噪声提供雾团形状。
#include "../math.slang"
#include "../noise.slang"

// 一层低空雾的参数；不同群系或天气换字段即可。
struct OgxFog
{
    float3 color; // 雾的环境色，线性空间。
    float density; // 基础高度处的密度，每公里。
    float heightFalloff; // 离开基础高度后的衰减距离，公里。
    float baseHeight; // 最浓的高度，公里。
    float noiseScale; // 雾团的水平尺度，每公里。
    float noiseStrength; // 噪声对密度的调制强度，零到一。
    float3 wind; // 水平风向，公里。
    float sunStrength; // 阳光在雾里的散射强度。
};

// 默认低空雾：贴地薄雾，密度适中，云影下会自然变暗。

// 高度雾、噪声雾与沿视线积分，具体实现在子文件。
#include "fog/density.slang"
// 末地涡旋、群系与下界雾，具体实现在子文件。
#include "fog/end.slang"

#endif
