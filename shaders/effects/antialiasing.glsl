// 抗锯齿：几何抖动与时间合成共用；示例 omniTaa(color, uv, metadata)。
#ifndef OMNI_ANTIALIASING
#define OMNI_ANTIALIASING
// @effect {"label":{"zh_cn":"抗锯齿","en_us":"Antialiasing"}}
// @option {"label":{"zh_cn":"抗锯齿算法","en_us":"Antialiasing mode"},"description":{"zh_cn":"零关闭，一快速边缘平滑，二带相机重投影的时间抗锯齿；动态物体保守降低历史。","en_us":"Off, FXAA, or camera-reprojected TAA with conservative dynamic rejection."}}
#define OMNI_AA_MODE 1 // [0 1 2]
// @option {"label":{"zh_cn":"时间历史权重","en_us":"History weight"}}
#define OMNI_TAA_WEIGHT 0.85 // [0.5 0.7 0.85 0.95]
vec2 omniJitter(int frame) {
    int i = frame % 8; // 八帧固定低差异序列。
    const vec2 samples[8] = vec2[8](vec2(0.5,0.3333),vec2(0.25,0.6667),vec2(0.75,0.1111),vec2(0.125,0.4444),vec2(0.625,0.7778),vec2(0.375,0.2222),vec2(0.875,0.5556),vec2(0.0625,0.8889));
    return samples[i]-0.5; // 返回以像素为单位的中心偏移。
}
// 重建必须在抖动函数之后引入。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
float omniDimension() {
#ifdef OMNI_NETHER
    return 2.0; // 下界历史签名。
#elif defined OMNI_END
    return 3.0; // 末地历史签名。
#else
    return 1.0; // 主世界历史签名。
#endif
}
bool omniHistoryValid() {
    vec4 size = texelFetch(colortex5,ivec2(0,0),0); // 固定位置保存尺寸和场景信息。
    vec4 camera = texelFetch(colortex5,ivec2(1,0),0); // 上一帧真实相机位置。
    return size.x==viewWidth && size.y==viewHeight && size.z==omniDimension() && size.w==float(frameCounter-1) && camera.w==size.w && length(camera.xyz-cameraPosition)<8.0; // 拒绝缩放、切维度、重载、断帧与传送。
}
vec3 omniFxaa(vec2 uv) {
    vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 使用当前分辨率。
    vec3 c = texture(colortex6,uv).rgb; // 中心线性颜色。
    vec3 n = texture(colortex6,clamp(uv+vec2(0,pixel.y),0.0,1.0)).rgb, s = texture(colortex6,clamp(uv-vec2(0,pixel.y),0.0,1.0)).rgb; // 上下像素。
    vec3 e = texture(colortex6,clamp(uv+vec2(pixel.x,0),0.0,1.0)).rgb, w = texture(colortex6,clamp(uv-vec2(pixel.x,0),0.0,1.0)).rgb; // 左右像素。
    float center = omniLuminance(c); // 比较边缘亮度范围。
    float minimum = min(center,min(min(omniLuminance(n),omniLuminance(s)),min(omniLuminance(e),omniLuminance(w))));
    float maximum = max(center,max(max(omniLuminance(n),omniLuminance(s)),max(omniLuminance(e),omniLuminance(w))));
    if (maximum-minimum<max(0.0312,maximum*0.125)) return c; // 平坦区域保留细节。
    float nw = omniLuminance(texture(colortex6,clamp(uv+vec2(-pixel.x,pixel.y),0.0,1.0)).rgb); // 西北角亮度。
    float ne = omniLuminance(texture(colortex6,clamp(uv+pixel,0.0,1.0)).rgb); // 东北角亮度。
    float sw = omniLuminance(texture(colortex6,clamp(uv-pixel,0.0,1.0)).rgb); // 西南角亮度。
    float se = omniLuminance(texture(colortex6,clamp(uv+vec2(pixel.x,-pixel.y),0.0,1.0)).rgb); // 东南角亮度。
    minimum = min(minimum,min(min(nw,ne),min(sw,se))); maximum = max(maximum,max(max(nw,ne),max(sw,se))); // 过滤结果须保留局部亮度范围。
    vec2 direction = vec2(-((nw+ne)-(sw+se)),(nw+sw)-(ne+se)); // 沿局部边缘方向搜索。
    float reduce = max((nw+ne+sw+se)*0.03125,0.0078125); // 低对比区域避免方向放大。
    direction = clamp(direction/(min(abs(direction.x),abs(direction.y))+reduce),-8.0,8.0)*pixel; // 搜索最多八像素。
    vec3 inner = (texture(colortex6,clamp(uv-direction/6.0,0.0,1.0)).rgb+texture(colortex6,clamp(uv+direction/6.0,0.0,1.0)).rgb)*0.5; // 内部二点颜色。
    vec3 outer = inner*0.5+(texture(colortex6,clamp(uv-direction*0.5,0.0,1.0)).rgb+texture(colortex6,clamp(uv+direction*0.5,0.0,1.0)).rgb)*0.25; // 外部二点扩展边缘。
    float resultLuma = omniLuminance(outer); // 外部过滤越界时使用较短范围。
    return resultLuma<minimum || resultLuma>maximum ? inner : outer; // 保留亮度边界，避免过度模糊。
}
// 调用位置：rendering/temporal.glsl；示例：omniTaa(color, texcoord, state)。
vec3 omniTaa(vec3 color, vec2 uv, out vec4 metadata) {
    vec3 view = omniSceneView(uv,false); // 当前真实深度。
    metadata = vec4(length(view),1.0,float(frameCounter),omniDimension()); // 每像素历史记录。
    if (texture(colortex6,uv).a<0.5 || texture(colortex8,uv).a<0.0) return color; // 叠层与动态水不积累底层几何的历史。
#if OMNI_AA_MODE == 2
    if (!omniHistoryValid() || texture(colortex1,uv).a==2.0 || omniSkyPixel(uv)) return color; // 手与背景保守不积累。
    vec3 world = omniWorld(view)+cameraPosition-previousCameraPosition; // 同一表面对应到上一帧相机。
    vec4 previous = gbufferPreviousProjection*gbufferPreviousModelView*vec4(world,1.0); // 撤销相机运动。
#ifdef DISTANT_HORIZONS
    if (texture(depthtex0,uv).r>=0.999999) previous = dhPreviousProjection*gbufferPreviousModelView*vec4(world,1.0); // 远景历史采用独立投影。
#endif
    if (previous.w<=0.0) return color; // 先拒绝无效齐次投影，避免除零产生NaN污染历史。
    vec2 previousUv = previous.xy/previous.w*0.5+0.5 + omniJitter(frameCounter-1)/vec2(viewWidth,viewHeight); // 上一帧抖动恢复。
    if (any(lessThan(previousUv,vec2(0))) || any(greaterThan(previousUv,vec2(1)))) return color; // 屏幕外拒绝历史，W已经在除法前检查。
    if (previousUv.y<1.0/viewHeight && previousUv.x<2.0/viewWidth) return color; // 元数据像素不能当深度读取。
    ivec2 oldPixel = clamp(ivec2(previousUv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 历史状态不能插值整数帧号与维度。
    vec4 old = texelFetch(colortex5,oldPixel,0); // 精确读取一个历史表面的深度与标记。
    if (texelFetch(colortex4,oldPixel,0).a<0.5) return color; // 上一帧覆盖层不能用底层深度参与历史。
    float expected = length((gbufferPreviousModelView*vec4(world,1.0)).xyz); // 比较同一米制距离。
    if (old.b!=float(frameCounter-1) || old.a!=omniDimension() || abs(old.r-expected)>max(0.15,expected*0.015)) return color; // 遮挡变化拒绝历史。
    vec3 minimum = color, maximum = color; // 历史限制在当前邻域颜色范围。
    vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 当前邻域尺寸。
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        vec3 c = texture(colortex6,clamp(uv+vec2(x,y)*pixel,0.0,1.0)).rgb; // 当前帧邻域。
        minimum = min(minimum,c); maximum = max(maximum,c); // 防止过时亮色拖影。
    }
    vec3 history = clamp(texture(colortex4,previousUv).rgb,minimum,maximum); // 色彩裁剪。
    float motion = length(previousUv-uv)*max(viewWidth,viewHeight); // 大运动降低历史权重。
    float difference = abs(omniLuminance(history)-omniLuminance(color))/max(omniLuminance(color),0.05); // 动态照明与运动物体保守拒绝。
    return mix(color,history,OMNI_TAA_WEIGHT*exp(-motion*0.03)*exp(-difference*2.0)); // 不声称拥有实体速度缓冲。
#else
    return color; // 关闭时不读取历史画面。
#endif
}
#endif
