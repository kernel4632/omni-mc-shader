/*
标题标志：世界加载后的一小段时间里，在场景中浮现 iterationT 的品牌图标，并把标题计数写进二号画面顶行。
来源：iterationT `Lib/IndividualFounctions/MotionBlur.glsl` 的 `title()` 与 `main` 里两段，配合 `Lib/Settings.glsl:481` 的 `#define TITLE` 一比一移植。
职责：`TitleLogo` 把图标贴在一张浮在相机前方的平面上，叠回线性场景颜色，并返回它的不透明度（原程序把这个值当泛光引导）；
     `UpdateTitleCounter` 每帧累加二号画面顶行横坐标二十那个像素的标题计数，让图标先浮现再慢慢淡出。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE8_PASS` 分支，先算 `MotionBlurSceneColor()`，再依次调用 `TitleLogo` 与 `UpdateTitleCounter`。
可复制示例：
    `bloomGuide = TitleLogo(color);`
    `data2 = UpdateTitleCounter(data2);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先提供）：
    `texCoord`、`texelCoord`、`screenSize`、`CurveToLinear`、`EXPOSURE_OUTPUT_FACTOR`、`MAIN_OUTPUT_FACTOR` 来自后期共享声明与共用数学；
    `ViewPos_From_ScreenPos_Raw` 来自 `common/coordinates.glsl`，`RayPlaneIntersection` 与 `hPI` 来自 `common/math.glsl`；
    `eyeRySmooth` 来自加载器输入；`colortex2` 里已有上一帧写下的自动曝光统计与标题计数。
关键设计原因与取舍：
    图标贴在一张浮在相机前方的固定平面上，位置和角度跟着相机俯仰与偏航的平滑值走，所以走动时看起来像浮在场景里的一张卡片；
    不透明度由二号画面顶行那个计数像素逐帧累加，再经一段反序的 `smoothstep` 映射，加载后先完全可见、几秒内淡出，重载或换维度时清零重新浮现。
    图标贴图走一个独立的二维采样器，不用八号画面：合成阶段的八号画面已经被预计算大气三维贴图占用，同一个名字不能再当二维用（见 `docs/parity.md` 第 37 条）。
    下界没有太阳，原程序在这里改用 `NetherLighting` 给图标染色并让半透明直接变不透明；本文件与后期共享头都会声明五个下界群系权重，
    同时引入会重复声明，所以下界暂按曝光染色（与原程序默认亮度下的观感接近），一并记录在 `docs/parity.md` 第 37 条。
*/
#ifndef OMNI_TITLE_INCLUDED // 只引入一次，避免选项、采样器与函数重复定义。
#define OMNI_TITLE_INCLUDED // 置上标记，后续再次引用直接跳过。
// @effect {"label":{"zh_cn":"标题标志","en_us":"Title Logo"}}
// @option {"label": {"zh_cn": "标题标志", "en_us": "Title Logo"}, "page": "about", "description": {"zh_cn": "世界加载后短暂浮现 iterationT 品牌图标，来源 iterationT `Lib/Settings.glsl:481` 的 `TITLE`。", "en_us": "Briefly fades in the iterationT brand logo after a world loads. From iterationT `Lib/Settings.glsl:481` `TITLE`."}}
#define OMNI_TITLE 1 // [0 1]

// 图标贴图：iterationT 自带的 `texture/itt320.png`，由 `rendering/pipeline.properties` 绑到合成阶段这个二维采样器上。
// 为什么单独开一个采样器：合成阶段的八号画面是大气三维贴图，图标不能借用同一个名字。
uniform sampler2D omniTitleTex;

#if OMNI_TITLE // 关闭时整个功能在编译期去掉，不占逐像素开销。

// --- 曝光：把二号画面顶行的自动曝光统计换算成图标要乘的亮度 ---
// 为什么乘两个管线系数：原程序把图标放在线性场景里，颜色要跟场景同一套单位才不会过曝。
float TitleExposure(){
	float encoded = texelFetch(colortex2, ivec2(0, screenSize.y - 1.0), 0).a; // 顶行横坐标零是自动曝光统计。
	return CurveToLinear(encoded) * (1500.0 / EXPOSURE_OUTPUT_FACTOR / MAIN_OUTPUT_FACTOR); // 换算到图标亮度。
}

// --- 标题计数：读出二号画面顶行的计数像素，映射成图标的不透明度 ---
// 计数每帧只增不减，用一段反序的 `smoothstep` 当边界：计数小的时候完全可见，变大后淡出。
float TitleCounter(){
	float counter = texelFetch(colortex2, ivec2(20, screenSize.y - 1.0), 0).a * 20.0; // 顶行横坐标二十是标题计数，乘二十放到计数尺度。
	return 1.0 - smoothstep(4.0, 7.0, counter); // 先算正序边界再取反，等价于原程序的反序写法，计数超过七就不再显示。
}

// --- 卡片：算一张浮在相机前方平面上的卡片与该像素的视线是否相交 ---
// 相机俯仰与偏航各转一个角度，把视线投到卡片平面上，落在范围内的才取图标贴图。
vec4 TitleCard(vec2 screenCoord){
	vec3 viewDir = normalize(ViewPos_From_ScreenPos_Raw(screenCoord, 1.0)); // 该像素的视线方向。
	vec3 camera = vec3(0.0, 0.0, 4.0); // 卡片在相机前方四格处。

	float angleRx = acos(dot(gbufferModelView[1].xyz, vec3(0.0, 0.0, -1.0))) - hPI; // 相机上方向与竖直方向的夹角。
	angleRx = -0.5 * angleRx + 0.1; // 卡片俯仰取这个夹角的一半再加一点偏移。
	mat3 Rx = mat3(1.0,  0.0,          0.0,
				   0.0,  cos(angleRx), sin(angleRx),
				   0.0, -sin(angleRx), cos(angleRx)); // 俯仰旋转矩阵。

	float angleRy = eyeRySmooth * 7.0; // 相机偏航速度的平滑值乘七当卡片偏航。
	mat3 Ry = mat3(cos(angleRy), 0.0, -sin(angleRy),
				   0.0,          1.0,  0.0,
				   sin(angleRy), 0.0,  cos(angleRy)); // 偏航旋转矩阵。
	Rx = Ry * Rx; // 先俯仰再偏航。

	vec3 op = Rx * camera; // 卡片中心方向先转过去。
	vec3 pp = Rx * viewDir; // 视线方向也一起转。
	#if MC_VERSION >= 11400 // 一点一四以后相机平移量进逆视图矩阵，按原程序带上。
		op = mat3(gbufferModelViewInverse) * op + gbufferModelViewInverse[3].xyz * 0.1; // 回世界空间并随相机平移。
		pp = mat3(gbufferModelViewInverse) * pp + gbufferModelViewInverse[3].xyz * 0.1; // 同上。
	#else // 旧版本不带平移量。
		op = mat3(gbufferModelViewInverse) * op; // 只回世界空间。
		pp = mat3(gbufferModelViewInverse) * pp; // 同上。
	#endif
	op = op * Ry; // 原程序再乘一次偏航。

	vec3 plane = mat3(gbufferModelView) * RayPlaneIntersection(op, pp, -gbufferModelViewInverse[2].xyz); // 卡片平面与视线的交点，回到视图空间。
	if (clamp(plane.xy, vec2(-1.9, -1.0), vec2(2.1, 1.0)) != plane.xy){ // 交点落在卡片范围外就没有图标。
		return vec4(0.0); // 返回空白样本。
	}
	vec2 cardUv = plane.xy * vec2(0.25, -0.25) + vec2(0.48, 0.28); // 交点换成贴图坐标。
	ivec2 cardTexel = ivec2(cardUv * 50.0) + ivec2(0, -4); // 换成贴图像素，和原程序一样上移四像素。
	return texelFetch(omniTitleTex, cardTexel, 0); // 取图标的颜色与透明度。
}

// --- 叠加图标：把卡片颜色按曝光调亮后混进线性场景，返回它的不透明度 ---
// 返回的不透明度被调用方当泛光引导；关掉标题标志时调用方直接不调用本函数。
float TitleLogo(inout vec3 color){
	float counter = TitleCounter(); // 当前的标题计数映射出的不透明度。
	if (counter <= 0.0){
		return 0.0; // 计数已经过界，直接跳过，不采样贴图。
	}
	vec4 card = TitleCard(texCoord); // 取该像素的图标样本。
	card.rgb *= TitleExposure(); // 图标颜色按曝光调亮，和场景同一套单位。
	card.a *= counter; // 再乘计数映射出的不透明度。
	color = mix(color, card.rgb, card.a); // 叠回线性场景颜色。
	return card.a; // 返回不透明度，调用方当泛光引导。
}

// --- 标题计数：每帧把二号画面顶行横坐标二十那个像素累加一点 ---
// 计数只增不减，重载或换维度时二号画面清零，图标才会重新浮现。
vec4 UpdateTitleCounter(vec4 data2){
	if (floor(gl_FragCoord.xy) == vec2(20.0, screenSize.y - 1.0)){ // 只改顶行横坐标二十这一个像素。
		data2.a = saturate(data2.a + min(frameTime, 0.5) * 0.05); // 每帧加零点零五乘帧时间，帧时间封顶半秒避免跳变。
	}
	return data2; // 其余像素原样保留。
}

#endif // 标题标志开关结束。
#endif // 文件守卫结束。
