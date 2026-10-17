/*
受伤与低血量画面表现：受击时给画面边缘闪一层红，血量低时边缘染红并随心跳脉冲，死亡时整屏压成暗红。
来源：从 `references/Eclipse/shaders/lib/gameplay_effects.glsl` 的 `applyGameplayEffects`（第 37 到 136 行）
  移植受伤、低血量与死亡三段；选项对照 Eclipse `lib/settings.glsl` 第 834 到 846 行的 `MOTION_AMOUNT`、
  `LOW_HEALTH_EFFECT`、`LOW_HEALTH_EFFECT_START`、`CRITICALLY_LOW_HEALTH_EFFECT_START`、`DAMAGE_TAKEN_EFFECT`。
调用位置：`rendering/final.glsl` 的片元阶段，在算出最终颜色、做过镜头形变之后、叠加抖动之前调用一次。
可复制示例：`color = omniHurtEffect(color, texCoord);`
调用前提（由调用方声明或带入）：`colortex1` 与 `frameTimeCounter` 由 `common/uniforms.glsl` 声明，
  `InterleavedGradientNoise` 由 `common/math.glsl` 提供；本文件在开启效果时自行声明 Iris 的玩家状态输入。
关键设计原因与取舍：
  一、默认关闭。`OMNI_HURT_EFFECT` 不开时整个效果被条件编译跳过，默认画面与现在完全一致。
  二、血量口径。Iris 的 `currentPlayerHealth` 是零到一的相对血量，创造与旁观模式给负一；
    乘 `maxPlayerHealth` 还原成半颗心，与 Eclipse 的阈值同一口径，低于阈值才触发。
  三、时间平滑的替代。Eclipse 用 Iris 自定义量 `smooth()` 对低血量与受击做时间平滑；本项目这一小步
    不能改 `rendering/pipeline.properties`，所以低血量改成对血量做平滑阶跃，受击没有血量历史，
    直接用 `is_hurt` 触发，且不再区分大伤小伤。这是已知的近似，过渡会比 Eclipse 稍硬。
  四、未移植的部分。同一段原程序里的镜头发水与着火形变依赖 Eclipse 平滑过的入水与离水自定义量，
    本步不移植，留给后续单独小步。
*/
#ifndef OMNI_HURT_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_HURT_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"受伤与低血量","en_us":"Hurt & low health"}}
// @option {"label":{"zh_cn":"受伤与低血量效果","en_us":"Hurt & low health effect"},"description":{"zh_cn":"受击闪红边、低血量染红心跳、死亡整屏暗红；默认关闭，关闭时画面与现在完全一致。来源 Eclipse `lib/gameplay_effects.glsl`。","en_us":"Red flash on hit, low-health red heartbeat and a dark red on death; off by default so the default look is unchanged. From Eclipse `lib/gameplay_effects.glsl`."}}
//#define OMNI_HURT_EFFECT
// @option {"label":{"zh_cn":"低血量红屏","en_us":"Low health red screen"},"description":{"zh_cn":"血量低时画面边缘染红并随心跳脉冲；默认开启，只有打开上面的总开关才生效。来源 Eclipse `LOW_HEALTH_EFFECT`。","en_us":"Red screen edges with a heartbeat pulse when health is low; on by default, only active when the master effect is enabled. From Eclipse `LOW_HEALTH_EFFECT`."}}
#define OMNI_HURT_LOW_HEALTH
// @option {"label":{"zh_cn":"受击闪红","en_us":"Damage flash"},"description":{"zh_cn":"受到伤害后短暂给画面边缘闪一层红；默认开启，只有打开总开关才生效。来源 Eclipse `DAMAGE_TAKEN_EFFECT`。","en_us":"A brief red flash on the screen edges after taking damage; on by default, only active when the master effect is enabled. From Eclipse `DAMAGE_TAKEN_EFFECT`."}}
#define OMNI_HURT_DAMAGE
// @option {"label":{"zh_cn":"低血量阈值","en_us":"Low health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）开始出现红屏；默认六点零，来源 Eclipse `LOW_HEALTH_EFFECT_START`。","en_us":"Red screen starts below this health in half-hearts; default 6.0, from Eclipse `LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_LOW_HEALTH_START 6.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"危急低血量阈值","en_us":"Critical health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）红屏更强；默认二点零，来源 Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`。","en_us":"The red screen gets stronger below this health in half-hearts; default 2.0, from Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_CRITICAL_START 2.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"心跳抖动强度","en_us":"Heartbeat distortion"},"slider":true,"description":{"zh_cn":"低血量时边缘随心跳的抖动量；默认零点二五，来源 Eclipse `MOTION_AMOUNT`。","en_us":"How much the edges wobble with the heartbeat at low health; default 0.25, from Eclipse `MOTION_AMOUNT`."}}
#define OMNI_HURT_MOTION 0.25 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]

// 加载器输入声明；调用方通常已先引入，这里再引入一次由守卫去重，保证单独引用也能编译。
#include "/common/uniforms.glsl"
// 共用数学：提供 `InterleavedGradientNoise`。
#include "/common/math.glsl"

// Iris 的玩家状态输入：只在开启效果且运行在 Iris 上时声明，避免在其它加载器上出现未声明标识符。
#if defined OMNI_HURT_EFFECT && defined IS_IRIS
uniform float currentPlayerHealth; // 相对血量，零到一；创造与旁观模式给负一。
uniform float maxPlayerHealth; // 最大血量，单位半颗心；创造与旁观模式给负一。
uniform bool is_hurt; // 玩家受击后短暂为真，对应原版的受击闪烁计时。
#endif

// --- 受伤与低血量 ---
// 参数 `color` 是当前最终画面色，`texcoord` 是零到一的屏幕坐标。
// 返回处理后的画面色；效果关闭时原样返回，默认画面不变。
vec3 omniHurtEffect(vec3 color, vec2 texcoord){
#if defined OMNI_HURT_EFFECT && defined IS_IRIS // 开启效果且是 Iris 才展开，否则直接返回。
	float absHealth = currentPlayerHealth * maxPlayerHealth; // 绝对血量，单位半颗心。
	bool alive = currentPlayerHealth > -1.0; // 负一是创造或旁观，不是有效生存态。
	bool isDead = alive && absHealth <= 0.0; // 生存态下血量归零就是死亡。

	float threeHeart = 0.0; // 低血量红屏与心跳的强度；未开低血量时保持零，心跳与形变随之消失。
	#if defined OMNI_HURT_LOW_HEALTH // 开启低血量时才按血量算强度。
		threeHeart = 1.0 - smoothstep(OMNI_HURT_LOW_HEALTH_START, OMNI_HURT_LOW_HEALTH_START + 1.0, absHealth); // 低于阈值拉满，高出一个半步的心回到零。
		float oneHeart = 1.0 - smoothstep(OMNI_HURT_CRITICAL_START, OMNI_HURT_CRITICAL_START + 1.0, absHealth); // 危急阈值同样做阶跃。
	#endif

	// 到画面中心的距离：中心接近零、边缘接近一，红边的形状由它决定，照原程序。
	float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0));
	float noise = InterleavedGradientNoise(gl_FragCoord.xy); // 每像素交错的零到一噪声，照原程序。

	// 心跳脉冲：正弦平方做出“砰、砰”的节奏，基值与幅度照原程序。
	float heartBeat = pow(sin(frameTimeCounter * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1;
	// 形变量：低血量时边缘随心跳抖动，强度由选项缩放；死亡时整个画面都在抖。
	float damageDistortion = vignette * noise * heartBeat * threeHeart * OMNI_HURT_MOTION;
	float distortMask = isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion;

	// 形变采样：以画面中心为轴把坐标向内收，畸变越大收得越多，边缘先动。
	vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask);
	vec3 distortedColor = texture(colortex1, zoomUV).rgb; // 取形变后的场景色。
	// 红色分量的亮度：只留红光，红屏与红边都用它。
	vec3 distortedLuma = vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07));

	#if defined OMNI_HURT_LOW_HEALTH // 低血量：边缘按强度染红。
		float colorLuma = dot(color, vec3(0.21, 0.72, 0.07)); // 当前像素的亮度。
		vec3 lumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 灰度画面在边缘偏红。
		color = mix(color, lumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart)); // 越危急混得越多。
	#endif
	#if defined OMNI_HURT_DAMAGE // 受击：给边缘闪一层红。
		float minorDamage = float(is_hurt); // 受击后短暂为一。
		color = mix(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 只作用在边缘。
	#endif
	if (isDead) color = distortedLuma * 0.35; // 死亡：整屏压成暗红。
#endif // 效果开关结束。
	return color; // 返回处理后的画面色。
}
#endif // 文件守卫结束。
