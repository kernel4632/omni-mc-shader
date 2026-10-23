/*
延迟程序共用的片元声明：把三个延迟阶段重复写过的像素坐标、顶点光色输入与阴影纹理集中到一处。
调用位置：`rendering/deferred_pass0.glsl` 到 `deferred_pass2.glsl` 的片元阶段，在输出变量之后引入。
可复制示例：`#include "/rendering/deferred_shared.glsl"`。
设计原因与取舍：这些声明在各程序里逐字相同，只是注释不同；集中一份后，新增输入只需改这里。
    顶点阶段不会引入本文件，`OMNI_FRAGMENT` 守卫让同一入口的顶点编译保持为空。
    这里不声明 `shadowtex1` 的比较采样器版本：合成程序把它声明成 `sampler2DShadow`，
    延迟程序需要普通 `sampler2D`，类型不同，不能合并。
*/
#ifndef OMNI_DEFERRED_SHARED_INCLUDED // 只展开一次，避免重复声明。
#define OMNI_DEFERRED_SHARED_INCLUDED // 置上标记。
#ifdef OMNI_FRAGMENT // 只有片元阶段需要这些输入与纹理。

// 加载器输入与共用数学：像素坐标、屏幕坐标与后续效果文件都要用。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 坐标换算与噪点：被引入的雾、全局光与焦散文件都会调用。
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"

// 当前像素坐标只在这里算一次，三个延迟程序口径一致。
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，纹理读取用。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标，雾与光照用。

// 顶点阶段算好的方向与光色，片元用同名输入接收。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 光方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。

// 阴影与辅助纹理：延迟程序只用普通二维采样器。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2D shadowtex1; // 阴影实心图。
uniform sampler2D shadowcolor0; // 阴影颜色图。
uniform sampler2D shadowcolor1; // 阴影法线天光图。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。

#endif // 片元阶段结束。
#endif // 文件守卫结束。
