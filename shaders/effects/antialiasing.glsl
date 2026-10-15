// 抗锯齿：本文件集中管理屏幕边缘的两件事——本帧几何抖动偏移，以及按相机重投影的时间抗锯齿。
// 调用位置：几何抖动在 rendering/terrain.glsl 与 rendering/distant.glsl 的顶点阶段调用 omniJitter；rendering/temporal.glsl 调用 omniTaa 完成时间合成；ambient.glsl 等效果复用 omniTemporalNoise。
// 可复制示例：`vec2 offset = omniJitter(frameCounter); vec3 out = omniTaa(color, texcoord, state);`
// 关键设计原因与取舍：抖动值必须来自同一个确定的序列，写历史和读历史才能精确对齐，所以抖动只在本文件定义一次；时间合成不依赖实体速度缓冲，只用相机重投影加邻域裁剪来保守接纳历史。
// 只保留一套时间重投影算法；强度由「抗锯齿强度」控制，关掉后直接输出当前帧。
// 降级约定：历史无效、首帧、重载、切维度、传送、分辨率变化、齐次除零或数值越界时，一律保守回退到当前帧颜色，宁可画面短暂不干净，也不制造拖影或污点。
#ifndef OMNI_ANTIALIASING
#define OMNI_ANTIALIASING

// --- 选项：抗锯齿开关、强度、历史稳定度与噪声重建 ---
// @effect {"label":{"zh_cn":"抗锯齿","en_us":"Antialiasing"}}
// @option {"label":{"zh_cn":"抗锯齿开关","en_us":"Antialiasing"},"description":{"zh_cn":"用逐帧重投影把边缘和噪点叠平滑；关掉只输出当前帧。","en_us":"Reprojects frame history to smooth edges and noise; off returns the current frame."}}
#define OMNI_AA_ENABLED
// @option {"label":{"zh_cn":"抗锯齿强度","en_us":"Antialiasing strength"},"description":{"zh_cn":"越平滑也越容易留下轻微拖影；取零等于关闭。","en_us":"More smoothing but also slight trails; zero equals off."},"slider":true}
#define OMNI_AA_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label":{"zh_cn":"历史稳定度","en_us":"History stability"},"slider":true}
#define OMNI_TAA_WEIGHT 0.85 // [0.5 0.7 0.85 0.95]
// @option {"label":{"zh_cn":"噪点重建开关","en_us":"Noise rebuild"},"description":{"zh_cn":"每帧旋转屏幕噪声相位，配合时间重投影重建去噪。","en_us":"Rotates screen noise each frame so the reprojection rebuilds a denoised result."}}
#define OMNI_TEMPORAL_DENOISE 1 // [0 1]

// --- 生成这一帧的几何抖动偏移 ---
// 顶点按这个偏移抖动，时间合成再按同一个序列撤销，两者对齐是历史不抖动的关键。
vec2 omniJitter(int frame) {
    int i = frame % 8; // 用八帧一循环的低差异序列；GLSL 对负数取模结果未定义，所以要自己回绕。
    if (i < 0) i += 8; // 帧号为负（首帧或重载）时回到合法下标，避免越界读取采样表。
    const vec2 samples[8] = vec2[8](vec2(0.5,0.3333),vec2(0.25,0.6667),vec2(0.75,0.1111),vec2(0.125,0.4444),vec2(0.625,0.7778),vec2(0.375,0.2222),vec2(0.875,0.5556),vec2(0.0625,0.8889)); // 八帧错开的像素内偏移，让时间合成每帧采到略有不同的位置。
    return samples[i]-0.5; // 减半把采样值变成以像素为单位、以画面中心为零点的偏移。
}
// --- 共享依赖：必须放在抖动之后 ---
// 坐标重建在撤销抖动时会调用上面的函数，所以引用只能写在这里，不能在文件开头。
#include "/common/coordinates.glsl"
// 数值工具（哈希、归一化、有限性判断等）供本文件其余函数使用。
#include "/common/math.glsl"

// --- 当前维度的历史签名 ---
// 每个维度一个固定值，写进历史元数据后用来判断历史是否属于同一个场景，切维度时据此作废。
float omniDimension() {
#ifdef OMNI_NETHER
    return 2.0; // 下界用一个固定签名，和主世界、末地区分开。
#elif defined OMNI_END
    return 3.0; // 末地用另一个固定签名，换维度后历史无法沿用。
#else
    return 1.0; // 主世界默认签名，也是没有维度宏时的保守取值。
#endif
}

// --- 上一帧历史画面是否还能用 ---
// 读取上一帧固定位置保存的元数据（尺寸、维度、帧号、相机位置），逐项与当前状态对照；
// 任何一项对不上都说明历史属于别的场景或已经断帧，直接判定无效，让合成阶段回退当前帧。
bool omniHistoryValid() {
    vec4 size = texelFetch(colortex5,ivec2(0,0),0); // 帧内固定像素保存的尺寸和场景信息。
    vec4 camera = texelFetch(colortex5,ivec2(1,0),0); // 相邻像素保存的上一帧真实相机位置。
    if (size.x!=viewWidth || size.y!=viewHeight) return false; // 分辨率变化后旧历史的像素网格不再对齐。
    if (size.z!=omniDimension()) return false; // 维度签名不同，说明历史来自另一个场景。
    if (size.w!=float(frameCounter-1) || camera.w!=size.w) return false; // 帧号不连续，说明发生过重载或断帧。
    return length(camera.xyz-cameraPosition)<8.0; // 相机瞬移过远时，上一帧世界位置已无参考意义。
}

// --- 时序噪声：每帧旋转相位 ---
// 用黄金比例常数把屏幕像素的哈希值逐帧平移，得到空间稳定、随时间旋转的噪声；
// 时间合成把多帧叠加后即可重建去噪，替代逐像素固定的噪声图案。
float omniTemporalNoise(vec2 pixel) {
    return fract(omniHash(pixel)+0.6180339887*float(frameCounter%64)); // 空间稳定且逐帧旋转，重建时不会留下固定图案。
}

// --- 当前帧三乘三邻域的颜色包围盒 ---
// 用当前像素周围九个样本求颜色最小值和最大值，作为历史颜色的接纳范围；
// 超出范围的历史说明对应点已经过时或错误，需要被夹回，否则会拖出旧画面的亮色或暗色。
void omniTaaBounds(vec2 uv, vec3 color, out vec3 minimum, out vec3 maximum) {
    minimum = color; // 以当前像素为初值，保证中心一定落在范围内。
    maximum = color; // 上下限同源，邻域只会扩大这个范围。
    vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 单个像素的屏幕步长，用来采样相邻像素。
    for (int y=-1;y<=1;y++)
        for (int x=-1;x<=1;x++) {
            vec3 sampleColor = texture(colortex6,clamp(uv+vec2(x,y)*pixel,0.0,1.0)).rgb; // 邻点当前帧的线性颜色。
            minimum = min(minimum,sampleColor); // 接纳范围下界。
            maximum = max(maximum,sampleColor); // 接纳范围上界，用来压掉过时亮色。
        }
}

// --- 时间合成：把上一帧颜色按相机重投影接纳进当前帧 ---
// 先按相机运动把当前表面重投影到上一帧，再用元数据、覆盖层和深度逐项确认历史可信；
// 可信的历史再夹进当前邻域范围并按运动、亮度差降低权重，任何一步不通过都返回当前帧颜色。
vec3 omniTaa(vec3 color, vec2 uv, out vec4 metadata) {
    vec3 view = omniSceneView(uv,false); // 当前像素的真实视空间位置，用来做重投影。
    metadata = vec4(length(view),1.0,float(frameCounter),omniDimension()); // 每像素记录深度、帧号和维度，供下一帧判断历史。
    if (texture(colortex6,uv).a<0.5 || texture(colortex8,uv).a<0.0) return color; // 叠层像素与退出历史的水面不参与底层几何的历史。
#ifdef OMNI_AA_ENABLED
    if (!omniHistoryValid() || texture(colortex1,uv).a==2.0 || omniSkyPixel(uv)) return color; // 历史无效、手部标记或天空都没有可靠世界位置，保守不积累。
    vec3 world = omniWorld(view)+cameraPosition-previousCameraPosition; // 把当前表面挪回上一帧相机所在的世界坐标。
    vec4 previous = gbufferPreviousProjection*gbufferPreviousModelView*vec4(world,1.0); // 用上一帧矩阵投影，得到该表面在上一帧的屏幕位置。
#ifdef DISTANT_HORIZONS
    if (texture(depthtex0,uv).r>=0.999999) previous = dhPreviousProjection*gbufferPreviousModelView*vec4(world,1.0); // 远景像素改用远景专用投影，近景矩阵对远景无效。
#endif
    if (previous.w<=0.0) return color; // 先拒绝无效的齐次投影，避免下一步除零产生数值污染历史。
    vec2 previousUv = previous.xy/previous.w*0.5+0.5 + omniJitter(frameCounter-1)/vec2(viewWidth,viewHeight); // 补回上一帧投影时加过的抖动，才能对齐到真实的上一帧像素。
    if (any(lessThan(previousUv,vec2(0))) || any(greaterThan(previousUv,vec2(1)))) return color; // 落在屏幕外说明上一帧看不到这个表面，历史不可用。
    if (previousUv.y<1.0/viewHeight && previousUv.x<2.0/viewWidth) return color; // 跳过保存元数据的固定像素，否则会把元数据当成深度来读取。
    ivec2 oldPixel = omniPixel(previousUv); // 帧号与维度是离散整数，历史状态必须精确采样到整数像素。
    vec4 old = texelFetch(colortex5,oldPixel,0); // 上一帧该像素的深度与标记。
    if (texelFetch(colortex4,oldPixel,0).a<0.5) return color; // 上一帧这里是覆盖层，深度不可信，不能用它参与历史。
    float expected = length((gbufferPreviousModelView*vec4(world,1.0)).xyz); // 用上一帧视图矩阵算出应有的米制深度。
    if (old.b!=float(frameCounter-1) || old.a!=omniDimension() || abs(old.r-expected)>max(0.15,expected*0.015)) return color; // 帧号、维度或深度任一对不上，说明对应点被遮挡或场景已变。
    vec3 minimum, maximum; // 当前邻域颜色范围，用来限制历史颜色。
    omniTaaBounds(uv,color,minimum,maximum); // 求出接纳范围，超出即视为过时。
    vec3 history = texture(colortex4,previousUv).rgb; // 上一帧该点的颜色，可能含未初始化或损坏的值。
    if (any(isnan(history)) || any(isinf(history))) history = color; // 非有限历史退回当前帧，避免数值污染扩散到后续帧。
    history = clamp(history,minimum,maximum); // 把历史夹进当前邻域范围，抑制过时亮色的拖影。
    float motion = length(previousUv-uv)*max(viewWidth,viewHeight); // 用像素为单位的运动量衡量重投影偏移。
    float difference = abs(omniLuminance(history)-omniLuminance(color))/max(omniLuminance(color),0.05); // 历史与当前的亮度差，越大越像动态照明或运动物体。
    return mix(color,history,OMNI_TAA_WEIGHT*OMNI_AA_STRENGTH*exp(-motion*0.03)*exp(-difference*2.0)); // 运动、亮度差越大历史权重越低；强度取零等于不接纳历史。
#else
    return color; // 关闭抗锯齿时只输出当前帧，不读取历史画面。
#endif
}
#endif
