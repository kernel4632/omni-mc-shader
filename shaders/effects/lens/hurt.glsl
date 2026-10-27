/*
效果文件 `effects/lens/hurt.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lens/hurt.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_LENS_HURT_INCLUDED
#define OMNI_EFFECT_LENS_HURT_INCLUDED
// @effect {"label":{"zh_cn":"受伤、血量与镜头发水","en_us":"Hurt, health & water on camera"}}
// @option {"label":{"zh_cn":"受伤与低血量效果","en_us":"Hurt & low health effect"},"description":{"zh_cn":"受击闪红边、重击整屏染红、低血量染红心跳、死亡整屏暗红；默认关闭，关闭时画面与现在完全一致。来源 Eclipse `lib/gameplay_effects.glsl`。","en_us":"Red edges on a hit, a full-screen red flash on a heavy hit, low-health red heartbeat and a dark red on death; off by default so the default look is unchanged. From Eclipse `lib/gameplay_effects.glsl`."}}
#define OMNI_HURT_EFFECT 0 // [0 1]
// @option {"label":{"zh_cn":"低血量红屏","en_us":"Low health red screen"},"description":{"zh_cn":"血量低时画面边缘染红并随心跳脉冲；默认开启，只有打开上面的总开关才生效。来源 Eclipse `LOW_HEALTH_EFFECT`。","en_us":"Red screen edges with a heartbeat pulse when health is low; on by default, only active when the master effect is enabled. From Eclipse `LOW_HEALTH_EFFECT`."}}
#define OMNI_HURT_LOW_HEALTH 1 // [0 1]
// @option {"label":{"zh_cn":"受击闪红","en_us":"Damage flash"},"description":{"zh_cn":"小伤闪红边（一次掉一点五颗心以上），重击整屏染红（一次掉三点五颗心以上）；默认开启，只有打开总开关才生效。来源 Eclipse `DAMAGE_TAKEN_EFFECT`。","en_us":"Red edges on a small hit (1.5 hearts or more in one go) and a full-screen red flash on a heavy hit (3.5 hearts or more); on by default, only active when the master effect is enabled. From Eclipse `DAMAGE_TAKEN_EFFECT`."}}
#define OMNI_HURT_DAMAGE 1 // [0 1]
// @option {"label":{"zh_cn":"低血量阈值","en_us":"Low health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）开始出现红屏；默认六点零，来源 Eclipse `LOW_HEALTH_EFFECT_START`。","en_us":"Red screen starts below this health in half-hearts; default 6.0, from Eclipse `LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_LOW_HEALTH_START 6.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"危急低血量阈值","en_us":"Critical health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）红屏更强；默认二点零，来源 Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`。","en_us":"The red screen gets stronger below this health in half-hearts; default 2.0, from Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_CRITICAL_START 2.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"心跳抖动强度","en_us":"Heartbeat distortion"},"slider":true,"description":{"zh_cn":"低血量时边缘随心跳的抖动量；默认零点二五，来源 Eclipse `MOTION_AMOUNT`。","en_us":"How much the edges wobble with the heartbeat at low health; default 0.25, from Eclipse `MOTION_AMOUNT`."}}
#define OMNI_HURT_MOTION 0.25 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"着火热浪","en_us":"On-fire heat"},"description":{"zh_cn":"身上着火时边缘染橙并随火焰抖动；默认开启，只有打开总开关才生效。来源 Eclipse `ON_FIRE_DISTORT_EFFECT`。","en_us":"Orange edges and a heat wobble while burning; on by default, only active when the master effect is enabled. From Eclipse `ON_FIRE_DISTORT_EFFECT`."}}
#define OMNI_HURT_FIRE 1 // [0 1]
// @option {"label":{"zh_cn":"溺水压暗","en_us":"Drowning darkening"},"description":{"zh_cn":"在水下且血量偏低时整屏偏蓝压暗；默认开启，只有打开总开关才生效。本项目拿不到氧气量，用“在水下且血量低于低血量阈值”近似，来源 Eclipse `DROWNING_EFFECT`。","en_us":"Bluish darkening while underwater at low health; on by default, only active when the master effect is enabled. Air level is unavailable here, so underwater plus low health is used as an approximation. From Eclipse `DROWNING_EFFECT`."}}
#define OMNI_HURT_DROWNING 1 // [0 1]

// @option {"label":{"zh_cn":"镜头发水","en_us":"Water on camera"},"description":{"zh_cn":"下雨、快速移动或在水下时在镜头上挂水珠，水珠把画面轻微抖动并糊开；默认关闭。这是近似：Eclipse 的原始效果依赖跨帧平滑的入水与离水自定义量，本项目拿不到，改用降雨湿润度、相机速度与是否在水下估算。","en_us":"Droplets on the lens that wobble and blur the view when it rains, while moving fast or while the eye is in water; off by default. Approximation: Eclipse drives this from cross-frame smoothed enter and exit water amounts, unavailable here, so wetness, camera speed and the underwater state are combined instead."}}
#define OMNI_WATER_ON_CAMERA 0 // [0 1]
// @option {"label":{"zh_cn":"镜头发水强度","en_us":"Water on camera strength"},"slider":true,"description":{"zh_cn":"水珠折射与糊开的强度；默认一点零，只在上面的镜头发水开启时生效。","en_us":"Strength of the droplet refraction and blur; default 1.0, only used when water on camera is on."}}
#define OMNI_WATER_ON_CAMERA_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
受伤与低血量画面表现：受击时给画面边缘闪一层红，重击时整屏染红，血量低时边缘染红并随心跳脉冲，死亡时整屏压成暗红。
来源：从 `references/Eclipse/shaders/lib/gameplay_effects.glsl` 的 `applyGameplayEffects`（第 37 到 136 行）
  移植受伤、低血量与死亡三段；选项对照 Eclipse `lib/settings.glsl` 第 834 到 846 行的 `MOTION_AMOUNT`、
  `LOW_HEALTH_EFFECT`、`LOW_HEALTH_EFFECT_START`、`CRITICALLY_LOW_HEALTH_EFFECT_START`、`DAMAGE_TAKEN_EFFECT`；
  小伤与重击的判定量 `MinorDamageTaken`、`CriticalDamageTaken` 由加载器按 `rendering/pipeline.properties`
  的自定义输入算好，来源 Eclipse `shaders.properties` 第 729 到 750 行。
调用位置：`rendering/final.glsl` 的片元阶段，在算出最终颜色、做过镜头形变之后、叠加抖动之前调用一次。
可复制示例：`color = omniHurtEffect(color, texCoord);`
调用前提（由调用方声明或带入）：`colortex1` 与 `frameTimeCounter` 由 `common/uniforms.glsl` 声明，
  `InterleavedGradientNoise` 由 `common/math.glsl` 提供；本文件在开启效果时自行声明 Iris 的玩家状态输入，
  并声明加载器算好的小伤与重击强度。
关键设计原因与取舍：
  一、默认关闭。`OMNI_HURT_EFFECT` 不开时整个效果被条件编译跳过，默认画面与现在完全一致。
  二、血量口径。Iris 的 `currentPlayerHealth` 是零到一的相对血量，创造与旁观模式给负一；
    乘 `maxPlayerHealth` 还原成半颗心，与 Eclipse 的阈值同一口径，低于阈值才触发红屏。
  三、小伤与重击的区分。判断一次掉了多少血需要跨帧的旧血量，GLSL 拿不到上一帧，交给加载器的 `smooth`
    在 `pipeline.properties` 里保存状态：受击瞬间血量立刻下降、平滑血量还在高位，两者之差就是掉落量，
    过阈值分别得到小伤（染红边缘）与重击（整屏染红）两个强度，照 Eclipse 原式。
  四、仍近似的部分。着火热浪用 `is_burning` 直接触发，没有跨帧平滑，火焰跳动靠每像素噪声；
    溺水按“在水下且血量低于低血量阈值”近似，因为 Iris 不提供氧气量；镜头发水单独成一个选项
    `OMNI_WATER_ON_CAMERA`（默认关闭），用降雨湿润度、相机速度与是否在水下估算，原因见 `omniWaterOnCamera`；
    低血量红屏仍用对血量的平滑阶跃，没走加载器的跨帧平滑（Eclipse 的 `oneHeart`/`threeHeart`）。
*/


// 加载器输入声明；调用方通常已先引入，这里再引入一次由守卫去重，保证单独引用也能编译。
#include "/common/uniforms.glsl"
// 共用数学：提供 `InterleavedGradientNoise`。
#include "/common/math.glsl"

// Iris 的玩家状态输入：只在开启效果且运行在 Iris 上时声明，避免在其它加载器上出现未声明标识符。
#if OMNI_HURT_EFFECT && defined IS_IRIS
uniform float currentPlayerHealth; // 相对血量，零到一；创造与旁观模式给负一。
uniform float maxPlayerHealth; // 最大血量，单位半颗心；创造与旁观模式给负一。
uniform bool is_burning; // 玩家着火时为真；本文件是唯一的声明处，别处要用需自行引入。
uniform float MinorDamageTaken; // 小伤强度，加载器按 `pipeline.properties` 每帧算好：一次掉一点五颗心以上，约一秒内淡出。
uniform float CriticalDamageTaken; // 重击强度，加载器按 `pipeline.properties` 每帧算好：一次掉三点五颗心以上，约三秒内淡出。
#endif

// --- 镜头发水（近似） ---
// 参数 `color` 是当前画面色、`texcoord` 是零到一的屏幕坐标；返回叠加水珠扰动后的画面色。
// 为什么是近似：Eclipse 用跨帧平滑的入水 `enterWater` 与离水 `exitWater` 决定水珠的出现与消散，
//   本项目这一步不能改绘制设置，拿不到这两个平滑量，改用降雨湿润度、相机速度与是否在水下估算。
vec3 omniWaterOnCamera(vec3 color, vec2 texcoord){
	#if OMNI_WATER_ON_CAMERA // 只在开启镜头发水时展开，默认关闭时本函数原样返回画面。
		float underWater = float(isEyeInWater == 1); // 眼睛在水下为一，用来给镜头挂一层水膜。
		float speed = length(cameraPosition - previousCameraPosition) / max(frameTime, 1e-4); // 相机移动速度，单位米每秒；帧时为零时用极小值兜底，避免除零。
		float motion = saturate(speed * 0.06); // 速度换算成零到一的晃动权重，约十六米每秒到顶；动得越快水珠抖得越厉害。
		float wet = saturate(max(wetness, underWater * 0.7)); // 镜头湿度：下雨取湿润度，在水下再补一份，两者取较大。
		vec2 dropUV = texcoord * vec2(aspectRatio, 1.0); // 水珠采样坐标先按宽高比校正，水珠才会是圆的而不是被横向拉长。
		dropUV.y -= frameTimeCounter * (0.03 + 0.05 * motion); // 随时间向下滑动，移动越快滑得越快，模拟水珠在镜头上往下流。
		float drops = texture(noisetex, dropUV).r; // 读共享蓝噪声当作水珠分布，复用现成贴图不新增资源。
		drops = saturate(drops - (1.0 - wet) * 0.7) * wet; // 只有湿度够、噪声又超过阈值的地方才形成水珠，湿度越低水珠越少。
		float mask = saturate(drops * OMNI_WATER_ON_CAMERA_STRENGTH) * (0.4 + 0.6 * motion); // 水珠折射强度：湿度决定有没有，速度决定抖多厉害。
		float film = underWater * 0.15; // 水下水膜：眼睛在水下时额外给一层固定的轻微折射，代表镜头与眼睛之间的水。
		vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - (mask + film) * 0.5); // 以画面中心为轴把坐标向内收，水珠与水膜处产生折射抖动。
		vec3 refracted = texture(colortex1, zoomUV).rgb; // 取折射后的画面色。
		vec3 blurred = (refracted + texture(colortex1, zoomUV + vec2(pixelSize.x, 0.0)).rgb + texture(colortex1, zoomUV + vec2(0.0, pixelSize.y)).rgb) / 3.0; // 取三处相邻色做平均，近似水膜把画面糊开。
		color = mix(color, mix(refracted, blurred, 0.5), saturate(mask * 3.0 + film)); // 水珠与水膜越强越偏向模糊折射，其余地方保持清晰。
	#endif // 镜头发水开关结束。
	return color; // 返回处理后的画面色。
}

// --- 受伤与低血量 ---
// 参数 `color` 是当前最终画面色，`texcoord` 是零到一的屏幕坐标。
// 返回处理后的画面色；效果关闭时原样返回，默认画面不变。
vec3 omniHurtEffect(vec3 color, vec2 texcoord){
	// 镜头发水先叠加：由独立选项 `OMNI_WATER_ON_CAMERA` 控制，不受受伤总开关影响。
	color = omniWaterOnCamera(color, texcoord);
#if OMNI_HURT_EFFECT && defined IS_IRIS // 开启效果且是 Iris 才展开，否则直接返回。
	float absHealth = currentPlayerHealth * maxPlayerHealth; // 绝对血量，单位半颗心。
	bool alive = currentPlayerHealth > -1.0; // 负一是创造或旁观，不是有效生存态。
	bool isDead = alive && absHealth <= 0.0; // 生存态下血量归零就是死亡。

	float threeHeart = 0.0; // 低血量红屏与心跳的强度；未开低血量时保持零，心跳与形变随之消失。
	#if OMNI_HURT_LOW_HEALTH // 开启低血量时才按血量算强度。
		threeHeart = 1.0 - smoothstep(OMNI_HURT_LOW_HEALTH_START, OMNI_HURT_LOW_HEALTH_START + 1.0, absHealth); // 低于阈值拉满，高出一个半步的心回到零。
		float oneHeart = 1.0 - smoothstep(OMNI_HURT_CRITICAL_START, OMNI_HURT_CRITICAL_START + 1.0, absHealth); // 危急阈值同样做阶跃。
	#endif

	// 到画面中心的距离：中心接近零、边缘接近一，红边的形状由它决定，照原程序。
	float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0));
	float noise = InterleavedGradientNoise(gl_FragCoord.xy); // 每像素交错的零到一噪声，照原程序。

	// 心跳脉冲：正弦平方做出“砰、砰”的节奏，基值与幅度照原程序。
	float heartBeat = pow(sin(frameTimeCounter * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1;
	// 形变量：低血量按心跳在边缘抖动；重击时把边缘抖动升级成整屏抖动；强度统一由选项缩放；死亡时整个画面都在抖。
	float damageDistortion = vignette * noise * heartBeat * threeHeart;
	#if OMNI_HURT_DAMAGE // 重击时整屏抖，照 Eclipse 把边缘权重换成「半个基础量加噪声」。
		damageDistortion = mix(damageDistortion, vignette * (0.5 + noise), CriticalDamageTaken);
	#endif
	damageDistortion *= OMNI_HURT_MOTION;
	float distortMask = isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion;

	// 形变采样：以画面中心为轴把坐标向内收，畸变越大收得越多，边缘先动。
	vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask);
	vec3 distortedColor = texture(colortex1, zoomUV).rgb; // 取形变后的场景色。
	// 红色分量的亮度：只留红光，红屏与红边都用它。
	vec3 distortedLuma = vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07));

	#if OMNI_HURT_LOW_HEALTH // 低血量：边缘按强度染红。
		float colorLuma = dot(color, vec3(0.21, 0.72, 0.07)); // 当前像素的亮度。
		vec3 lumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 灰度画面在边缘偏红。
		color = mix(color, lumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart)); // 越危急混得越多。
	#endif
	#if OMNI_HURT_DAMAGE // 受击：小伤染红边缘，重击整屏染红，照 Eclipse。
		color = mix(color, distortedLuma, vignette * sqrt(min(MinorDamageTaken, 1.0))); // 小伤只在边缘，越靠边越红。
		color = mix(color, distortedLuma, sqrt(CriticalDamageTaken)); // 重击不乘边缘权重，整屏变红，越重越红。
	#endif
	#if OMNI_HURT_FIRE // 着火：边缘染橙并随火焰抖动。
		float burning = float(is_burning); // 身上着火时为一。
		vec3 fireEdge = vec3(1.0, 0.45, 0.12) * max(dot(color, vec3(0.21, 0.72, 0.07)), 0.15); // 橙色边缘的基色，至少留一点亮。
		color = mix(color, mix(color, fireEdge, 0.6), vignette * burning * (0.5 + noise * 0.5)); // 越靠边缘染得越多，噪声让火焰跳动。
	#endif
	#if OMNI_HURT_DROWNING // 溺水：水下且血量偏低时整屏偏蓝压暗。
		// 为什么这样近似：原版溺水按氧气量表现，Iris 不提供氧气量；这里用“在水下且血量低于低血量阈值”代表已经快淹死。
		float drowning = float(isEyeInWater == 1) * step(absHealth, OMNI_HURT_LOW_HEALTH_START); // 在水下且血量偏低时为一时压暗。
		color = mix(color, color * vec3(0.55, 0.7, 1.0), drowning * 0.5); // 偏蓝压暗一半。
	#endif
	if (isDead) color = distortedLuma * 0.35; // 死亡：整屏压成暗红。
#endif // 效果开关结束。
	return color; // 返回处理后的画面色。
}
#endif // OMNI_EFFECT_LENS_HURT_INCLUDED
