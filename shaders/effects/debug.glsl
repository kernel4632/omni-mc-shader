/*
 * 调试显示：选择场景颜色、深度图或画面坐标，帮助定位绘制问题。
 * 调用位置：rendering/final.glsl。
 * 示例：debugColor(scene.rgb, texture(depthtex0, texcoord).r, texcoord)。
 */

// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label":{"zh_cn":"调试显示","en_us":"Debug view"},"description":{"zh_cn":"0：正常画面；1：原始深度；2：画面坐标。深度通常接近白色。","en_us":"0: scene; 1: raw depth; 2: screen coordinates. Raw depth is often near white."}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2]

// --- 选择要观察的中间数据 ---
vec3 debugColor(vec3 scene, float depth, vec2 coordinates) {
#if OMNI_DEBUG_VIEW == 1
    return vec3(depth); // 用灰度展示加载器提供的原始深度。
#elif OMNI_DEBUG_VIEW == 2
    return vec3(coordinates, 0.0); // 红绿通道分别显示横纵坐标。
#else
    return scene; // 默认不改变玩家画面。
#endif
}
