/*
水洼调节：把 Eclipse 的两项水洼可调量——水洼尺寸与湿面反射锐度——单独成一个文件。
来源：选项取 `references/Eclipse/shaders/lib/settings.glsl` 第三百五十九到三百六十一行，算法取
  `references/Eclipse/shaders/dimensions/composite1.fsh` 第八百四十七到九百三十三行的 `applyPuddles`。
职责：只提供两个纯计算函数和它们的选项，不读写中间画面，也不声明加载器输入。
调用位置：`OmniPuddleCoverage` 已由 `effects/water/water.glsl` 的 `GetRainNormal` 在「仅水洼」模式里调用，
  覆盖范围因此跟随 `OMNI_PUDDLE_SIZE`；入参是该处的湿润度 `wet` 与水洼形状噪声 `puddleNoise`。
  `OmniPuddleRoughness` 需要材质粗糙度，而本项目的粗糙度在合成阶段由 `MaterialFromTex` 解出，
  那份文件不在本次接线范围，所以这个函数当前没有调用点，`OMNI_PUDDLE_REFLECTION_SHARPNESS` 暂时不生效；
  缺的原因是粗糙度只存在于合成阶段，接它会越出本次允许改动的文件范围。
可复制示例（`halfWet`、`puddleNoise`、`wetnessStages` 由调用方按现有湿润流程准备）：
  `float puddles = OmniPuddleCoverage(halfWet, puddleNoise);`
  `float wetnessStages = max(puddles, fullWet) * lightmap;`
  `roughness = OmniPuddleRoughness(roughness, 0.5 * (1.0 + snowR), wetnessStages);`
与现有选项的关系：`effects/water/water.glsl` 的 `OMNI_PUDDLE_MODE` 决定雨点涟漪铺满整片湿面还是只出现在低洼处；
  本文件两项是在它之上细化水洼形状与湿面反射，属于并列增强，不替换它，也不依赖它。
默认中性：`OMNI_PUDDLE_SIZE` 默认 1.0，是 Eclipse 的参考值；`OMNI_PUDDLE_REFLECTION_SHARPNESS` 默认 0.0，
  按下面的公式令粗糙度不被湿润改写，接入后默认画面保持现状；Eclipse 该选项默认 0.9 会改粗糙度，故这里默认关闭它的影响。
*/
#ifndef OMNI_PUDDLE_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_PUDDLE_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"水洼","en_us":"Puddles"}}
// 菜单页放在「天气与季节」：积水由降雨产生，Eclipse 也把 `Puddle_Size`、`Puddle_Reflection_Sharpness` 放在天气一页；
// 放在水一页会让水分类多出一个子页面，且与 Eclipse 的分页不一致。
// @option {"label":{"zh_cn":"水洼尺寸","en_us":"Puddle size"},"page":"weather","description":{"zh_cn":"低洼处积水范围的大小，调大后水洼更大更连片，调小更零散；来源 Eclipse 的 `Puddle_Size`，默认 1.0 与参考一致。","en_us":"Size of the puddles that form in low spots; larger makes them bigger and better connected. From Eclipse `Puddle_Size`; default 1.0 matches the reference."}}
#define OMNI_PUDDLE_SIZE 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"湿面反射锐度","en_us":"Wet reflection sharpness"},"page":"weather","description":{"zh_cn":"湿表面反射的清晰程度，调大后积水表面更接近镜面；默认 0.0 表示不改动当前粗糙度，Eclipse 默认 0.9。","en_us":"How sharp reflections get on wet ground; larger is more mirror-like. Default 0.0 leaves roughness unchanged; Eclipse default is 0.9."}}
#define OMNI_PUDDLE_REFLECTION_SHARPNESS 0.0 // [0.0 0.9 0.925 0.95 0.975 1.0]

// 水洼覆盖：由湿润度与低洼噪声算出零到一的积水覆盖，供调用方决定水洼范围与暗化强度。
// 为什么先减噪声：噪声代表地势起伏，湿润高于噪声处才是真正低洼，减掉噪声就露出水洼边界。
// 为什么用五次方加指数：让阈值附近的过渡更陡、远离阈值处更平，水洼边缘自然又不整片糊死。
float OmniPuddleCoverage(float halfWet, float noise){
	float puddles = max(halfWet - noise, 0.0); // 只有湿润高于噪声阈值的低洼处才开始积水。
	puddles = clamp(halfWet - exp(-25.0 * puddles * puddles * puddles * puddles * puddles * OMNI_PUDDLE_SIZE), 0.0, 1.0); // 指数衰减给出覆盖率，`OMNI_PUDDLE_SIZE` 越大衰减越慢、水洼越大。
	return puddles; // 返回零到一的积水覆盖：零是没有水洼，一是一整片积水。
}

// 湿面反射锐度：把干表面粗糙度往「湿表面粗糙度」混合，湿得越深反射越清晰。
// `OMNI_PUDDLE_REFLECTION_SHARPNESS` 就是混合比例的上限，默认 0.0 时原样返回，不改变画面。
// 数学与 Eclipse 一致：`mix(roughness, wetRoughness, wetnessStages * 锐度)`，此处不做额外夹取，保持等价。
// 当前没有调用点：本项目的材质粗糙度在合成阶段由 `MaterialFromTex` 解出，接它要改那份文件，越出本次接线范围。
float OmniPuddleRoughness(float roughness, float wetRoughness, float wetnessStages){
	return mix(roughness, wetRoughness, wetnessStages * OMNI_PUDDLE_REFLECTION_SHARPNESS); // 湿润阶段乘锐度作为混合比例，锐度为零则不混合。
}
#endif // 文件守卫结束。
