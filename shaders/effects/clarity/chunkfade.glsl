/*
区块淡入：让原版新加载的区块逐渐显现，而不是整块突然跳出。
来源：从 `references/Eclipse/shaders/dimensions/all_solid.vsh`、`all_solid.fsh`、`all_translucent.vsh`、
  `all_translucent.fsh` 的 `VANILLA_CHUNK_FADING` 段移植；选项在 Eclipse `lib/settings.glsl:1038`。
职责：把 Eclipse 在顶点与片元里对 Iris 区块淡入进度 `mc_chunkFade` 的三处处理整理成纯函数：
  顶点把进度取成正的零到一、可选地把远处的块从下方滑入；片元按进度抖动丢弃，半透明的水按进度压透明度。
为什么单独成一个文件：这三处分别落在顶点与片元两个阶段、地形与水两个程序，但数学只有一种；
  放在一处便于对照 Eclipse，也避免在多个绘制主体里各抄一份。
调用位置（本节暂未接入任何程序，待绘制主体添加调用点；下面给出可直接复制的最小接法）：
  一、`gbuffers_terrain` 顶点阶段（Eclipse `all_solid.vsh:255-256`）：先请求加载器特性 `FADE_VARIABLE`（见下），
    再写 `#ifdef IRIS_FEATURE_FADE_VARIABLE` 内 `float chunkFade = omniChunkFadeValue(mc_chunkFade);`，
    并把 `chunkFade` 作为插值量经几何阶段转发到片元。
  二、`gbuffers_terrain` 片元阶段（Eclipse `all_solid.fsh:572-578`）：先算本像素抖动（开时间抗锯齿用蓝噪声，
    否则用交错梯度噪声），再写 `if (omniChunkFadeDiscard(chunkFade, dither)) discard;`。
  三、`gbuffers_water` 片元阶段（Eclipse `all_translucent.fsh:662-670`）：
    写 `gl_FragData[0] = omniChunkFadeWaterColor(gl_FragData[0], chunkFade);`。
  这些调用点所在文件不在本子任务的允许改动范围，所以本文件当前不被任何程序引用。
关键设计原因与取舍：
  一、默认关闭。`OMNI_CHUNK_FADE` 取零时三个函数都原样返回，绘制主体即使接上也不改变画面。
  二、依赖的加载器能力。进度值 `mc_chunkFade` 是 Iris 在 `gbuffers_*.vsh` 里按需提供的顶点属性，
    只在原版具备区块淡入动画的版本（Minecraft 一月二一点一一点以后）才存在；使用前必须在
    `rendering/pipeline.properties` 的 `iris.features.optional` 里加上 `FADE_VARIABLE`，再以
    `IRIS_FEATURE_FADE_VARIABLE` 宏判断是否可用，不可用时整套效果不参与编译。
  三、抖动的来源。Eclipse 开时间抗锯齿时用蓝噪声、否则用交错梯度噪声；这里把抖动作为形参传入，
    由调用方按当前是否开时间抗锯齿选择，函数本身不绑定具体噪声，便于复用与单独测试。
  四、滑动入场的洞穴判断。Eclipse 用 `caveDetection`（洞穴探测量）决定是否滑动；本项目的等效量是
    `eyeBrightnessZeroSmooth`（看不到天空的平滑标记），调用方取其相反量传进来即可。
*/
#ifndef OMNI_CHUNK_FADE_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_CHUNK_FADE_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"区块淡入","en_us":"Chunk fade in"}}
// @option {"label":{"zh_cn":"区块淡入","en_us":"Chunk fade in"},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"淡入","en_us":"Fade in"},"2":{"zh_cn":"淡入加滑动","en_us":"Fade in + slide in"}},"description":{"zh_cn":"新加载的区块逐渐显现，而不是整块突然跳出；默认关闭。来源 Eclipse `VANILLA_CHUNK_FADING`，需要 Iris 的区块淡入特性。","en_us":"Newly loaded chunks fade in instead of popping in; off by default. From Eclipse `VANILLA_CHUNK_FADING`; needs the Iris chunk fade feature."}}
#define OMNI_CHUNK_FADE 0 // [0 1 2]

// --- 顶点：把 Iris 的区块淡入进度取成正的零到一 ---
// 参数 `rawFade` 是加载器给的 `mc_chunkFade`；它在方块未淡入时为负、淡入完成时为一。
// 为什么取绝对值：Eclipse 在顶点写 `data_out.chunkFade = abs(mc_chunkFade)`，负值同样表示“未淡入”。
float omniChunkFadeValue(float rawFade){
#if OMNI_CHUNK_FADE > 0 // 开启时才读取进度。
	return clamp(abs(rawFade), 0.0, 1.0); // 取正并夹到零到一。
#else // 关闭时恒为一，等于没有淡入。
	return 1.0; // 直接返回满进度，绘制主体接上也不改变画面。
#endif
}

// --- 片元：按进度抖动丢弃像素，让新块逐渐出现 ---
// 参数 `fade` 是上一步的零到一进度；`dither` 是每个像素各不相同的零到一噪声。
// 为什么用平方根：Eclipse 用 `sqrt(chunkFade)` 当阈值，进度越小时丢弃的像素越多，视觉上像渐显。
bool omniChunkFadeDiscard(float fade, float dither){
#if OMNI_CHUNK_FADE > 0 // 开启时才按进度丢弃。
	return sqrt(fade) < dither; // 等价 Eclipse 的 `if (sqrt(chunkFade) < BN) discard;`。
#else // 关闭时从不丢弃。
	return false; // 整块直接显示。
#endif
}

// --- 片元：半透明的方块与水按进度压低透明度 ---
// 参数 `color` 是本像素最终要写的颜色，`fade` 是零到一进度。
// 为什么只改透明度而不用丢弃：半透明层若靠丢弃像素淡入，水面会闪断；压透明度更平滑，照 Eclipse。
vec4 omniChunkFadeWaterColor(vec4 color, float fade){
#if OMNI_CHUNK_FADE > 0 // 开启时才按进度压透明度。
	color.a *= sqrt(fade); // 照 Eclipse 的 `gl_FragData[0].a *= sqrt(chunkFade);`。
#endif
	return color; // 返回处理后的颜色，关闭时就是原值。
}

// --- 顶点：滑动档让远处的新块从下方滑入 ---
// 参数 `viewPos` 是视空间坐标，`fade` 是零到一进度，`caveMask` 是洞穴遮罩（一表示在洞里），
// `farPlane` 是远裁剪距离。
// 为什么只压低远处的纵坐标：Eclipse 只对超过二十五米且还没淡入完的块下移，近处不动，避免脚下穿帮。
vec3 omniChunkFadeSlide(vec3 viewPos, float fade, float caveMask, float farPlane){
#if OMNI_CHUNK_FADE > 1 // 只有“淡入加滑动”档才移动顶点。
	viewPos.y += -45.0 * (1.0 - fade) * (1.0 - caveMask) * smoothstep(25.0, farPlane, length(viewPos)); // 下移量照 Eclipse。
#endif
	return viewPos; // 返回（可能已下移的）视空间坐标。
}
#endif // 文件守卫结束。
