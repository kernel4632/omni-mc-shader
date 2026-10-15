// 水：解析波浪、盖斯特纳海浪、凹凸细节与水面折射反射的合成。
// 管什么：本文件只管水面这一件事——顶点高度、表面法线和屏幕合成颜色；
//   它不安排绘制顺序，也不复制其他效果的算法，绘制顺序见 rendering/terrain.glsl 与 rendering/composite.glsl。
// 调用位置：
//   rendering/terrain.glsl 顶点阶段用 omniOceanHeight 抬升水面顶点，片元阶段用 omniWaterNormal 造波；
//   rendering/composite.glsl 屏幕合成阶段用 omniWater 做折射、吸收与反射。
// 可复制示例：
//   取某点高度：`float h = omniWaterHeight(p, world.y);`
//   由高度得到法线：`vec3 n = omniWaterNormal(world, normal);`
//   合成颜色：`vec3 lit = omniWater(color, view, n, texcoord);`
// 设计原因与取舍：
//   高度只有一个来源：顶点位移和片元法线都读 omniWaterHeight，避免两边各写一套公式而对不上。
//   波浪只作用在顶面：瀑布与水流的侧面法线接近垂直，若也按水平位置造波，水面会和真实几何脱节。
//   折射必须防泄漏：偏移后的采样点若落到漂在水面前方的物体上，会把前景颜色漏进水里，所以偏移后要回头验证。
//   吸收按可见光分波段：红光衰减最快，水越深越偏青绿，最终趋近水体散射色。
//   内部数据互相信任：只在真正的边界（屏幕外、无效深度、非法高度）检查一次，层与层之间直接传值。
#ifndef OMNI_WATER
#define OMNI_WATER
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"水波强度","en_us":"Wave strength"},"slider":true}
#define OMNI_WAVE_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"水折射","en_us":"Water refraction"}}
#define OMNI_WATER_REFRACTION
// @option {"label":{"zh_cn":"雨滴水纹","en_us":"Rain ripples"}}
#define OMNI_RAIN_RIPPLES
// @option {"label":{"zh_cn":"玩家互动水纹","en_us":"Player ripples"},"description":{"zh_cn":"相机靠近水面移动时生成解析圆环；不是物理模拟，不读取其他实体。","en_us":"Analytic rings near a moving camera, not a fluid simulation or other entity tracking."}}
//#define OMNI_PLAYER_RIPPLES
// @option {"label":{"zh_cn":"水波凹凸细节","en_us":"Water bump detail"},"description":{"zh_cn":"在解析波上叠加多层程序噪声，增加水面细碎起伏。","en_us":"Adds multi-octave procedural noise on top of the analytic waves for fine ripples."}}
#define OMNI_WATER_BUMP 1 // [0 1]
// @option {"label":{"zh_cn":"物理海浪","en_us":"Ocean waves"},"description":{"zh_cn":"盖斯特纳波同时抬升顶点与法线，侧面与瀑布保持原法线。","en_us":"Gerstner waves lift vertices and normals together; side faces keep their normals."}}
#define OMNI_OCEAN_WAVES 1 // [0 1]
// 反射和坐标重建的共用实现：水面反射复用它读取已保存的不透明画面。
#include "/effects/reflection.glsl"
// --- 水体光学常数 ---
// 红衰减最快、绿居中、蓝最慢，所以水越深越偏青绿，最终趋向水体散射色。
// 只在这一个地方定义：水面合成与水下雾都从这里取，避免两处各写一份而对不上数值。
const vec3 omniWaterAbsorbance = vec3(0.19,0.065,0.035); // 每米吸收系数，红最高。
const vec3 omniWaterScatter = vec3(0.015,0.075,0.095); // 水体自身散射色，深度足够时趋向它。
// 按距离对颜色做分波段吸收并混入散射：`distance` 是光在水里走过的米数。
vec3 omniWaterTransmit(vec3 color, float distance) {
    vec3 absorbed = exp(-omniWaterAbsorbance*distance); // 各波段仍然保留的比例。
    return color*absorbed+omniWaterScatter*(1.0-absorbed); // 被吸收掉的部分趋向散射色。
}
// --- 解析波 ---
// 解析波是直接套公式算出的波，不用模拟，便宜且稳定；这里由三部分组成：
//   两个方向不同的正弦交叉，形成不会整齐滚动的较大起伏；
//   雨的涟漪，按空间格确定落点；
//   玩家涟漪，相机贴水移动时出现的圆环。
// 为什么用世界坐标而不是屏幕坐标：世界锚定让波跟着水面走，不随镜头漂移。
float omniWave(vec2 p, float relativeHeight) {
    float t = frameTimeCounter; // 游戏暂停时由加载器时间行为决定，本文件不额外冻结时间。
    float wave = sin(dot(p,vec2(0.65,0.3))+t*1.2)*0.06 + sin(dot(p,vec2(-0.2,0.8))-t*0.9)*0.04; // 两个方向与速度都不同的正弦，避免看出明显重复。
#ifdef OMNI_RAIN_RIPPLES
    vec2 cell = floor(p*0.7); // 把水面切成约一点四米一格，每格固定一个雨滴落点。
    vec2 center = (cell+vec2(omniHash(cell),omniHash(cell+8.2)))/0.7; // 用格坐标算落点，同一格永远落在同一点，波纹可重复。
    float age = fract(t*0.8+omniHash(cell+1.3)); // 每格起始相位不同，雨滴不会同时出现。
    float radius = length(p-center); // 当前点到本格落点的水平距离。
    wave += rainStrength*sin(radius*22.0-age*14.0)*exp(-radius*3.0)*(1.0-age)*0.025; // 向外扩散的环，随时间变淡，雨越大越明显。
#endif
#ifdef OMNI_PLAYER_RIPPLES
    float speed = length(cameraPosition-previousCameraPosition)/max(frameTime,0.001); // 由相邻两帧相机位置差得到移动速度。
    float r = length(p-cameraPosition.xz); // 到玩家的水平距离。
    float proximity = 1.0-smoothstep(0.5,2.5,abs(relativeHeight)); // 相机与水面垂直距离超过两米半就淡出，避免飞在天上仍冒圈。
    wave += proximity*min(speed,2.0)*sin(r*8.0-t*4.0)*exp(-r)*0.025; // 环强度同时受水平和高度距离限制，移动越快越明显。
#endif
    return wave*OMNI_WAVE_STRENGTH; // 波强度为零时整体归零，法线不再变化。
}
// --- 凹凸细节 ---
// 解析波和盖斯特纳海浪负责大起伏，这里用多层程序噪声补高频小涟漪，
// 频率越高振幅越小，避免近看发花；三层共用同一时间，保证细节和波形一起动。
float omniWaterDetail(vec2 p) {
    float t = frameTimeCounter; // 与解析波、海浪共享同一时间。
    float d = omniNoise(vec3(p*0.35,t*0.6))*0.02; // 中频涟漪，负责看得见的细浪。
    d += omniNoise(vec3(p*1.1,t*1.1))*0.008; // 高频细节，负责近看时的小颗粒。
    d += omniNoise(vec3(p*2.4,-t*1.4))*0.004; // 极细纹理并反向流动，打散规则重复感。
    return d*OMNI_WAVE_STRENGTH; // 与波强度共同缩放，关到零时细节消失。
}
// --- 盖斯特纳海浪 ---
// 盖斯特纳波给每层波一个方向、频率和振幅，再逐层叠加；这里只做垂直位移，不做水平挤压。
// 为什么单独成函数：海浪是大尺度、慢速、随波强度整体缩放的位移，顶点和法线都要用，
// 由 omniWaterHeight 调用，保证顶点抬升和片元法线来自同一份高度，不会错位。
float omniOceanHeight(vec2 p) {
#if OMNI_OCEAN_WAVES == 0
    return 0.0; // 关闭海浪时高度为零，顶点不动、法线也不变，等价于没有这一层。
#else
    float t = frameTimeCounter; // 游戏时间驱动海浪起落。
    float height = 0.0; float amplitude = 0.5; float frequency = 0.08; // 起始振幅和频率，决定最大浪高与波长。
    vec2 direction = normalize(vec2(1.0,0.3)); // 第一层浪的方向。
    for (int i=0;i<4;i++) {
        height += amplitude*sin(dot(direction,p)*frequency+t*(1.0+frequency)); // 按当前方向和频率叠加一层波。
        direction = vec2(direction.x*0.6-direction.y*0.8,direction.x*0.8+direction.y*0.6); // 旋转方向，避免四层同向叠成一条。
        amplitude *= 0.5; frequency *= 1.7; // 每层振幅减半、频率变高，形成由大到细的自然层次。
    }
    return height*OMNI_WAVE_STRENGTH; // 同样随波强度缩放。
#endif
}
// --- 合成高度 ---
// 把三种波加在一起，作为唯一的波高来源：大尺度海浪 + 解析波 + 凹凸细节。
// 法线有限差分和顶点位移都读这个函数，任何一层调整都会同时反映到顶点和法线。
float omniWaterHeight(vec2 p, float relativeHeight) {
    float height = omniOceanHeight(p)+omniWave(p,relativeHeight); // 先叠大尺度海浪和解析波。
#if OMNI_WATER_BUMP == 1
    height += omniWaterDetail(p); // 再补细碎凹凸。
#endif
    return height; // 波强度已在各层内部缩放，这里不再重复乘。
}
// --- 水面法线 ---
// 用高度差近似波浪倾斜：取横纵各一小步的高度差（中央差分），足够表现波浪倾斜，比解析求导便宜。
// 只对顶面造波：瀑布和水流的侧面法线接近垂直，这些面若也造波会和真实几何脱节；
// 波强度为零时同样直接返回原法线，让选项能彻底关掉波浪。
vec3 omniWaterNormal(vec3 world, vec3 originalNormal) {
    vec3 worldNormal = omniNormalize(mat3(gbufferModelViewInverse)*originalNormal); // 原表面朝向由真实几何提供，转到世界空间判断。
    if (OMNI_WAVE_STRENGTH<=0.0 || worldNormal.y<0.9) return originalNormal; // 顶面之外和零强度都保留原法线。
    vec2 p = (world+cameraPosition).xz; // 波浪锚定在世界坐标，随水面移动而不是随镜头漂移。
    float center = omniWaterHeight(p,world.y); // 中心点高度，用相机相对水面高度作为近水互动的基准。
    float slopeX = (center-omniWaterHeight(p+vec2(0.08,0.0),world.y))/0.08; // 横轴高度梯度，八厘米步长对应细波尺度。
    float slopeZ = (center-omniWaterHeight(p+vec2(0.0,0.08),world.y))/0.08; // 纵轴高度梯度，与横轴对称。
    vec3 tilted = omniNormalize(vec3(slopeX,1.0,slopeZ)); // 有限差分只扰动顶面，非零的垂直分量保证法线仍朝上。
    if (!(tilted.y>0.0)) return originalNormal; // 高度样本非法时退回原法线，避免 NaN 污染整幅画面。
    return omniNormalize(mat3(gbufferModelView)*tilted); // 合成阶段要用视空间法线，这里转回去。
}
// --- 水面合成 ---
// 折射：按法线把取样位置略作偏移，模拟光线在水面处弯折；浅水偏移小，避免整片画面扭曲。
// 防泄漏：若偏移后的位置属于漂在水面前方的物体，用它会显影前景颜色，所以这种情况拒绝偏移。
// 吸收：水体对红绿蓝的吸收速度不同，红最快、蓝最慢，越深越偏青绿，深水趋近水体散射色。
// 反射：按菲涅耳强度把水面反射混进来；反射强度开关关掉时整段反射都不参与。
// 调用位置：rendering/composite.glsl；示例：omniWater(color, view, waterNormal, texcoord)。
// 第一个参数 `color` 目前不参与运算，保留它是为了和各调用处、以及未来的底色混合保持一致。
vec3 omniWater(vec3 color, vec3 view, vec3 normal, vec2 uv) {
    vec2 refracted = uv; // 默认不折射，直接用原屏幕位置。
    float waterDepth = length(omniSceneView(uv,true))-length(view); // 底面到水面的真实距离：不透明深度减去水面深度。
    float thickness = waterDepth>0.0 ? min(waterDepth,100.0) : 0.0; // 非法或负距离按零厚度，避免 NaN 传播，同时限制在零到一百米。
#ifdef OMNI_WATER_REFRACTION
    vec2 candidate = clamp(uv+normal.xy*0.018*min(thickness,3.0),vec2(0.002),vec2(0.998)); // 浅水折射弱、深水折射强，偏移始终留在屏幕内。
    if (length(omniSceneView(candidate,true))>length(view)+0.05) refracted = candidate; // 只有偏移后仍在水面之后才采用，防止前景颜色漏进水里。
#endif
    vec3 transmitted = omniWaterTransmit(texture(colortex3,refracted).rgb,thickness); // 不透明快照含底面辐射，坐标可能已被折射偏移过；再按水体分波段吸收并趋向散射色。
    if (OMNI_REFLECTION_STRENGTH<=0.0) return transmitted; // 反射关闭时直接返回水色，不采样反射。
    float fresnel = 0.02+0.98*pow(1.0-max(dot(normal,omniNormalize(-view)),0.0),5.0); // 正对水面反射弱，掠射角反射强。
    return mix(transmitted,omniReflected(view,normal,0.06),fresnel*OMNI_REFLECTION_STRENGTH); // 按菲涅耳强度在透射和反射之间混合。
}
#endif
