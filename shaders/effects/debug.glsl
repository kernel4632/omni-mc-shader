/*
 * 调试显示：选择场景颜色、深度图或画面坐标，帮助定位绘制问题。
 * 调用位置：rendering/final.glsl。
 * 示例：debugColor(scene.rgb, texture(depthtex0, texcoord).r, texcoord)。
 */

// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label": {"zh_cn": "调试显示", "en_us": "Debug view"}, "description": {"zh_cn": "0：正常画面；1：原始深度；2：画面坐标。深度通常接近白色。", "en_us": "0: scene; 1: raw depth; 2: screen coordinates. Raw depth is often near white."}, "values": {"0": {"zh_cn": "正常画面", "en_us": "Scene"}, "1": {"zh_cn": "原始深度", "en_us": "Raw depth"}, "2": {"zh_cn": "画面坐标", "en_us": "Coordinates"}, "3": {"zh_cn": "几何法线", "en_us": "Normals"}, "4": {"zh_cn": "材质参数", "en_us": "Material"}, "5": {"zh_cn": "原版光照", "en_us": "Light data"}}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2 3 4 5]
// @option {"label":{"zh_cn":"性能计时","en_us":"Frame-time bar"},"description":{"zh_cn":"在屏幕左下角画一条横条显示每帧耗时，越长越慢；这是整帧时间，不是逐效果耗时。","en_us":"Draws a bar in the bottom-left showing per-frame time, longer means slower; this is total frame time, not per-effect."}}
//#define OMNI_PROFILER

// 性能计时：加载器只给整帧耗时，没有逐效果计时，所以这里只画一条按耗时长短变化的横条。
// 满格约三十毫秒，接近三十帧；快帧偏绿、慢帧偏红，方便一眼看出卡顿。
vec3 omniProfiler(vec3 color, vec2 coordinates) {
#ifdef OMNI_PROFILER
    vec2 pixel = coordinates*vec2(viewWidth,viewHeight); // 屏幕像素坐标，左下角为原点。
    float filled = clamp(frameTime*1000.0/33.0,0.0,1.0); // 把毫秒换算成零到一的填充比例，满格约三十三毫秒。
    if (pixel.x < 160.0 && pixel.y < 8.0) { // 只画左下角一小块，不遮挡画面主体。
        float lit = pixel.x/160.0 < filled ? 1.0 : 0.0; // 横条以内是点亮的像素。
        color = mix(vec3(0.04),mix(vec3(0.2,0.9,0.35),vec3(0.95,0.2,0.2),filled),lit); // 快帧偏绿、慢帧偏红。
    }
#endif
    return color; // 未开启时原样返回。
}

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
