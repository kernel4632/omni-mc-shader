/*
 * 调试显示：选择场景颜色、深度图或画面坐标，帮助定位绘制问题。
 * 调用位置：rendering/final.glsl。
 * 示例：debugColor(scene.rgb, texture(depthtex0, texcoord).r, texcoord)。
 */

// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label":{"zh_cn":"调试显示","en_us":"Debug view"},"description":{"zh_cn":"0：正常画面；1：原始深度；2：画面坐标。深度通常接近白色。","en_us":"0: scene; 1: raw depth; 2: screen coordinates. Raw depth is often near white."}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2 3 4 5]

// --- 选择要观察的中间数据 ---
vec3 debugColor(vec3 scene, float depth, vec2 coordinates) {
#if OMNI_DEBUG_VIEW == 1 // 深度直接观察实际场景输入。
    return vec3(depth); // 用灰度展示加载器提供的原始深度。
#elif OMNI_DEBUG_VIEW == 2 // 坐标用于定位屏幕取样偏移。
    return vec3(coordinates, 0.0); // 红绿通道分别显示横纵坐标。
#elif OMNI_DEBUG_VIEW == 3 // 法线用于核对几何元数据。
    return texture(colortex1,coordinates).rgb; // 观察实际几何法线编码。
#elif OMNI_DEBUG_VIEW == 4
    return texture(colortex2,coordinates).rgb; // 观察粗糙度、反射与自发光。
#elif OMNI_DEBUG_VIEW == 5
    return texture(colortex7,coordinates).rgb; // 观察原版光照输入。
#else
    return scene; // 默认不改变玩家画面。
#endif
}
