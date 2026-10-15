// 镜头：统一处理色差、景深、运动模糊、耀斑和暗角；无效输入时保守回退为清晰原色。
// 调用位置：rendering/final.glsl 在线性空间里叠加镜头效果。
// 可复制示例：`scene = omniLens(scene, texcoord) + omniBloom(texcoord);`
#ifndef OMNI_LENS
#define OMNI_LENS
// @effect {"label":{"zh_cn":"镜头","en_us":"Lens"}}
// @option {"label":{"zh_cn":"景深","en_us":"Depth of field"}}
//#define OMNI_DOF
// @option {"label":{"zh_cn":"运动模糊","en_us":"Motion blur"},"description":{"zh_cn":"基于相机运动，手持物不模糊；不包含实体速度。","en_us":"Camera motion only; excludes hands and has no entity velocity."}}
//#define OMNI_MOTION_BLUR
// @option {"label":{"zh_cn":"暗角强度","en_us":"Vignette"},"slider":true}
#define OMNI_VIGNETTE 0.0 // [0.0 0.1 0.25 0.5]
// @option {"label":{"zh_cn":"色差强度","en_us":"Chromatic aberration"}}
#define OMNI_CHROMATIC 0.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"镜头耀斑","en_us":"Lens flare"},"description":{"zh_cn":"从屏幕太阳亮部生成鬼影与光环，被遮挡时自动减弱。","en_us":"Draws ghosts and a halo from the on-screen sun highlight, fading when occluded."}}
#define OMNI_LENS_FLARE 1 // [0 1]
// @option {"label":{"zh_cn":"散景光圈形状","en_us":"Bokeh aperture"},"description":{"zh_cn":"零为圆形散景，一为六边形光圈，使失焦高光成多边形。","en_us":"Zero is a circular blur; one is a hexagonal aperture for polygonal highlights."}}
#define OMNI_BOKEH_SHAPE 1 // [0 1]
// 时间重投影、深度和镜头颜色来自统一的屏幕协议。
#include "/effects/antialiasing.glsl"

// 屏幕坐标转成合法像素编号，取样都落在画面内。
ivec2 omniLensPixel(vec2 uv) {
    return clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 边界夹紧，避免越界读取元数据。
}
// 读取一个镜头颜色样本：色差始终先于景深和运动模糊。
vec3 omniLensSample(vec2 uv) {
    vec3 color = texture(colortex0,uv).rgb; // 当前样本保持线性颜色。
    if (OMNI_CHROMATIC<=0.0) return color; // 关闭色差时不读取额外颜色样本。
    vec2 offset = (uv-0.5)*OMNI_CHROMATIC/vec2(viewWidth,viewHeight); // 画面边缘的色差更明显。
    color.r = texture(colortex0,clamp(uv+offset,0.0,1.0)).r; // 红色向外偏移。
    color.b = texture(colortex0,clamp(uv-offset,0.0,1.0)).b; // 蓝色向内偏移。
    return color; // 返回已经完成色差的线性颜色。
}

// 光圈形状半径：多边形光圈在给定角度的边界半径比例。
float omniApertureRadius(float angle) {
#if OMNI_BOKEH_SHAPE == 0
    return 1.0; // 圆形光圈边界半径为常数。
#else
    const float blades = 6.0; // 六片光圈叶片。
    float sector = 6.2831853/blades; // 每片占据的角度。
    float local = abs(mod(angle,sector)-sector*0.5); // 相对最近边中点的角度。
    return cos(sector*0.5)/cos(local); // 边心距到多边形边界的比例。
#endif
}
// 读取一个景深样本：先拒绝手和无效透明像素，再对有效样本做散焦。
vec3 omniFocusSample(vec2 uv) {
    ivec2 pixel = omniLensPixel(uv); // 所有类别读取最近元数据。
    vec4 geometry = texelFetch(colortex1,pixel,0); // 精确读取手和表面类别。
    vec4 surface = texelFetch(colortex7,pixel,0); // 精确读取几何有效标记。
    vec3 color = omniLensSample(uv); // 即使景深关闭也保留统一色差顺序。
    if (surface.a<0.5 || geometry.a==2.0) return color; // 覆盖层和手没有单一表面深度，不做景深。
#ifndef OMNI_DOF
    return color; // 关闭景深时不读取额外深度，也不进入采样循环。
#else
    ivec2 centerPixel = ivec2(viewWidth*0.5,viewHeight*0.5); // 自动对焦使用屏幕中心。
    vec4 centerGeometry = texelFetch(colortex1,centerPixel,0); // 中心类别同样使用最近像素。
    float focus = length(omniSceneView(vec2(0.5),false)); // 中央普通表面作为焦点。
    if (centerGeometry.a==2.0) focus = length(omniView(vec2(0.5),texture(depthtex2,vec2(0.5)).r)); // 手挡住中心时使用手之前深度。
    float distance = length(omniSceneView(uv,false)); // 当前表面真实距离。
    float radius = min(abs(distance-focus)/max(distance,0.1)*8.0,8.0); // 弥散范围保持有限。
    if (isnan(radius)) return color; // 深度重建异常时保留清晰原色。
    vec3 sum = color; float weight = 1.0; // 当前样本先参与平均。
    for (int i=0;i<8;i++) {
        float angle = float(i)*2.399963; // 散焦样本角度。
        float shaped = radius*omniApertureRadius(angle); // 光圈形状调制样本半径。
        vec2 sampleUv = clamp(uv+vec2(cos(angle),sin(angle))*shaped/vec2(viewWidth,viewHeight),0.0,1.0); // 生成屏幕内样本。
        ivec2 samplePixel = omniLensPixel(sampleUv); // 样本元数据使用最近像素。
        if (texelFetch(colortex1,samplePixel,0).a==2.0 || texelFetch(colortex7,samplePixel,0).a<0.5 || length(omniSceneView(sampleUv,false))<distance*0.75) continue; // 手、覆盖层和前景遮挡不泄漏。
        sum += omniLensSample(sampleUv); weight += 1.0; // 色差和景深顺序保持一致。
    }
    return sum/weight; // 只按有效样本归一化。
#endif
}

// 计算相机运动模糊：所有无效情况提前返回，循环只处理有效快门样本。
vec3 omniMotionBlur(vec3 color, vec2 uv) {
#ifndef OMNI_MOTION_BLUR
    return color; // 关闭运动模糊时没有深度、历史或矩阵读取。
#else
    ivec2 pixel = omniLensPixel(uv); // 当前元数据精确读取。
    if (texelFetch(colortex1,pixel,0).a==2.0 || texelFetch(colortex7,pixel,0).a<0.5 || texelFetch(colortex0,pixel,0).a<0.5) return color; // 手、覆盖层和无效历史保持清晰。
    if (omniSkyPixel(uv)) return color; // 天空没有可追踪表面。
    if (length(cameraPosition-previousCameraPosition)>=8.0) return color; // 传送或重载帧拒绝历史位移。
    vec3 currentView = omniSceneView(uv,false); // 当前深度恢复表面位置。
    vec3 absoluteWorld = omniWorld(currentView)+cameraPosition; // 转为绝对世界位置。
    vec3 previousView = (gbufferPreviousModelView*vec4(absoluteWorld-previousCameraPosition,1.0)).xyz; // 用上一帧相机重建位置。
    vec4 projected = gbufferPreviousProjection*vec4(previousView,1.0); // 普通表面使用普通历史投影。
#ifdef DISTANT_HORIZONS
    if (omniDistantPixel(uv,false)) projected = dhPreviousProjection*vec4(previousView,1.0); // DH表面使用独立历史投影。
#endif
    if (projected.w<=0.0 || any(isnan(projected))) return color; // 除法前拒绝相机后方与非有限投影。
    vec2 previousUnjittered = projected.xy/projected.w*0.5+0.5; // AA0与AA1始终使用未抖动的上一帧投影。
    vec2 previousUv = previousUnjittered; // 最终历史坐标默认等于未抖动位置。
    vec2 currentUnjittered = uv; // 当前坐标默认保持原位置。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    previousUv = previousUnjittered+omniJitter(frameCounter-1)/vec2(viewWidth,viewHeight); // 只有TAA开启时恢复上一帧抖动。
    currentUnjittered -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 撤销当前帧采样抖动。
#endif
    if (any(lessThan(previousUv,vec2(0))) || any(greaterThan(previousUv,vec2(1)))) return color; // 屏幕外历史拒绝。
    vec2 velocity = clamp(currentUnjittered-previousUnjittered,vec2(-0.05),vec2(0.05)); // AA0与AA1不计算抖动，TAA只比较去抖动坐标。
    vec3 sum = color; float weight = 1.0; // 当前像素先进入快门平均。
    for (int i=1;i<6;i++) {
        vec2 sampleUv = clamp(uv-velocity*float(i)/6.0,0.0,1.0); // 沿相机轨迹取样。
        ivec2 samplePixel = omniLensPixel(sampleUv); // 采样类别精确读取。
        if (texelFetch(colortex1,samplePixel,0).a==2.0 || texelFetch(colortex7,samplePixel,0).a<0.5) continue; // 手和覆盖层不进入快门。
        sum += omniFocusSample(sampleUv); weight += 1.0; // 每个样本保留景深与色差顺序。
    }
    return sum/weight; // 按实际有效样本归一化。
#endif
}

// 屏幕太阳位置：把视空间太阳方向投影到屏幕，背后或屏幕外返回假。
bool omniSunScreen(out vec2 sunUv) {
    vec3 sunView = omniNormalize(sunPosition); // 加载器提供的视空间太阳方向。
    if (sunView.z>=0.0) return false; // 太阳在相机后方不产生耀斑。
    vec4 clip = gbufferProjection*vec4(sunView,0.0); // 方向投影到裁剪空间。
    if (clip.w<=0.0) return false; // 齐次投影非正时拒绝，避免除零翻转。
    sunUv = clip.xy/clip.w*0.5+0.5; // 归一化到屏幕坐标。
    return all(greaterThanEqual(sunUv,vec2(0))) && all(lessThanEqual(sunUv,vec2(1))); // 只保留屏幕内太阳。
}
// 镜头耀斑：从太阳亮部生成鬼影与光环，遮挡时由亮部自动减弱。
vec3 omniLensFlare(vec2 uv) {
#if OMNI_LENS_FLARE == 0
    return vec3(0.0); // 关闭时没有额外采样。
#else
    vec2 sunUv; // 屏幕太阳坐标。
    if (!omniSunScreen(sunUv)) return vec3(0.0); // 太阳不在画面内不产生耀斑。
    float source = max(omniLuminance(texture(colortex0,sunUv).rgb)-1.0,0.0); // 现有亮部提供光源强度。
    vec2 aspect = vec2(viewWidth/viewHeight,1.0); // 圆形柔光使用屏幕宽高比。
    vec2 axis = sunUv-0.5; // 屏幕中心到太阳的方向。
    vec3 flare = vec3(0.0); // 累加鬼影与光环。
    for (int i=1;i<=4;i++) {
        vec2 ghostUv = 0.5-axis*float(i)*0.6; // 沿中心反向排列的鬼影位置。
        float distance = length((uv-ghostUv)*aspect); // 到鬼影中心的距离。
        flare += exp(-distance*distance*80.0)*vec3(0.6,0.75,1.0)/float(i+1); // 冷色渐弱的圆形鬼影。
    }
    float halo = exp(-pow(length((uv-sunUv)*aspect),2.0)*6.0); // 太阳近旁的柔光环。
    flare += halo*vec3(1.0,0.86,0.62); // 暖色主耀光。
    float daylight = smoothstep(-0.15,0.1,dot(omniNormalize(sunPosition),omniNormalize(upPosition))); // 太阳高度限制白昼耀斑。
    return flare*source*daylight; // 遮挡与夜晚自动减弱。
#endif
}
// 最终镜头顺序：景深、运动模糊、暗角；调用位置是 rendering/final.glsl。
vec3 omniLens(vec3 color, vec2 uv) {
#if defined OMNI_DOF || defined OMNI_MOTION_BLUR
    color = omniFocusSample(uv); // 开启高级镜头时先处理色差与景深。
#else
    if (OMNI_CHROMATIC>0.0) color = omniLensSample(uv); // 只有色差时跳过景深循环。
#endif
    color = omniMotionBlur(color,uv); // 运动模糊函数内部处理关闭和所有早返回。
    color += omniLensFlare(uv); // 镜头耀斑在暗角之前叠加。
    return color*(1.0-OMNI_VIGNETTE*smoothstep(0.1,0.7,length(uv-0.5))); // 最后才应用暗角。
}
#endif
