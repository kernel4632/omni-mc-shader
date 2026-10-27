/*
效果文件 `effects/entity/entity.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/entity/entity.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_ENTITY_ENTITY_INCLUDED
#define OMNI_EFFECT_ENTITY_ENTITY_INCLUDED
// @effect {"label":{"zh_cn":"生物与玩家","en_us":"Mobs & player"}}
// @option {"label":{"zh_cn":"实体状态颜色","en_us":"Entity Status Color"},"description":{"zh_cn":"实体受伤时贴图会染上的红色。","en_us":"The red tint a mob shows when hurt."}}
#define OMNI_ENTITIES_STATUS_COLOR 1 // [0 1]
// @option {"label":{"zh_cn":"实体眼部发光","en_us":"Entity Eyes Lighting"},"description":{"zh_cn":"让末影人、蜘蛛、坚守者等实体的部分纹理发光。","en_us":"Makes parts of endermen, spiders and wardens glow."}}
#define OMNI_EYES_LIGHTING 1 // [0 1]
// @option {"label":{"zh_cn":"手部视场角模式","en_us":"Hand FOV Mode"},"description":{"zh_cn":"默认、跟随游戏设置或跟随光影设置；跟随游戏设置会使用选项里的视场角。","en_us":"Default, follow the game FOV, or follow the shader FOV; game mode uses the option value."},"values":{"0":{"zh_cn":"默认","en_us":"Default"},"1":{"zh_cn":"跟随游戏设置","en_us":"Follow Game Setting"},"2":{"zh_cn":"跟随光影设置","en_us":"Follow Shader Setting"}}}
#define OMNI_HAND_FOV_MODE 0 // [0 1 2]
// @option {"label":{"zh_cn":"手部视场角","en_us":"Hand FOV"},"description":{"zh_cn":"跟随光影设置时手持物的视场角，七十是原版大小。","en_us":"Held item FOV when following the shader; 70 is the vanilla size."},"slider":true}
#define OMNI_HAND_FOV 70.0 // [30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
生物与玩家：实体受伤状态色、发光眼开关与手持物视场角。
来源：实体状态色与手部视场角照 iterationT `Lib/Programs/Gbuffers/Entities_FS.glsl`、`Entities_VS.glsl` 一比一移植；
  发光眼在 iterationT 里没有算法，只作为一个程序开关存在，见下方说明。
调用位置：
  实体片元：解出底色后调用 `albedo.rgb = EntityStatusColor(albedo.rgb, entityColor);`；
  手持物顶点：算裁剪坐标时调用 `gl_Position = HandFovProjection(gbufferProjection, aspectRatio) * viewPos;`。
可复制示例：
  `albedo.rgb = EntityStatusColor(albedo.rgb, entityColor);`
  `gl_Position = HandFovProjection(gbufferProjection, aspectRatio) * viewPos;`
调用前提（iterationT 原样保留）：实体状态色依赖调用方声明的 `entityColor`；手持物视场角依赖加载器提供的
  `MC_HAND_DEPTH` 宏与 `aspectRatio` 输入，只在手持物程序里调用。
设计原因与取舍：发光眼在 iterationT 里靠 `shaders.properties` 里开关整个 `gbuffers_spidereyes` 程序实现，
  光源码中只有一句空的判断，没有任何算法，所以这里只保留选项本身，真正的启用写在 `rendering/pipeline.properties`
  的 `program.world0/gbuffers_spidereyes.enabled=OMNI_EYES_LIGHTING`，语义与 iterationT 一致。
*/
// 手持物视场角与状态色都用到共用数学与角度常数。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 实体状态色：受伤时把底色朝受伤颜色混，混合量取自受伤颜色的透明度。
vec3 EntityStatusColor(vec3 albedo, vec4 entityColor){
	#if OMNI_ENTITIES_STATUS_COLOR // 关闭时直接返回原底色。
		albedo = mix(albedo, entityColor.rgb, vec3(entityColor.a)); // 按受伤颜色本身的透明度混合。
	#endif
	return albedo; // 交回处理后的底色。
}
// 手持物视场角：按模式改写投影矩阵的焦点与深度项，得到与原版不同大小或深度的手持物。
// 调用前提：只在手持物程序里调用，`MC_HAND_DEPTH` 由加载器提供。
mat4 HandFovProjection(mat4 projection, float aspectRatio){
	#if OMNI_HAND_FOV_MODE == 1 // 跟随游戏设置时只改深度项，沿用游戏给的焦距。
		projection[2][2] *= MC_HAND_DEPTH; // 按游戏的手部深度缩放。
	#elif OMNI_HAND_FOV_MODE == 2 // 跟随光影设置时改写焦距。
		projection[1][1] = 1.0 / tan(OMNI_HAND_FOV * (PI / 360.0)); // 由视场角反推纵向焦距。
		projection[0][0] = projection[1][1] / aspectRatio; // 横向按屏幕宽高比缩放，形状不变形。
		projection[2][2] *= MC_HAND_DEPTH; // 同样按游戏的手部深度缩放。
	#endif
	return projection; // 交回改写后的投影矩阵。
}
// 末地传送门的十六层贴图：每层用不同缩放、旋转与时间偏移叠同一条投影坐标，颜色权重照原程序。
// 为什么放在实体效果里：这是方块实体的贴图合成算法，绘制主体的片元只负责在 `OMNI_BLOCK_PASS` 里调用一次。
// 调用前提：`frameTimeCounter` 由加载器输入声明；`tex` 是方块实体贴图采样器。
mat2 mat2_rotate_z(float radian){
	return mat2(cos(radian), -sin(radian), sin(radian), cos(radian)); // 标准二维旋转矩阵。
}
// 生成第若干层传送门贴图的变换矩阵。
mat4 end_portal_layer(float layer){
	const mat4 scaleTranslate = mat4(0.5, 0.0, 0.0, 0.25, // 传送门贴图的缩放平移矩阵。
									 0.0, 0.5, 0.0, 0.25,
									 0.0, 0.0, 1.0, 0.0,
									 0.0, 0.0, 0.0, 1.0);
	mat4 translate = mat4(1.0, 0.0, 0.0, 17.0 / layer, // 逐层偏移。
						  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (frameTimeCounter * 0.0005), // 纵向随时间缓慢流动。
						  0.0, 0.0, 1.0, 0.0,
						  0.0, 0.0, 0.0, 1.0);
	mat2 rotate = mat2_rotate_z(radians((layer * layer * 4321.0 + layer * 9.0) * 2.0)); // 每层不同角度。
	mat2 scale = mat2((4.5 - layer / 4.0) * 2.0); // 每层不同缩放。
	return mat4(scale * rotate) * translate * scaleTranslate; // 合成完整变换。
}
vec3 EndPortalColor(sampler2D texSampler, vec4 portalCoord){
	const vec3 COLORS[16] = vec3[]( // 十六层传送门贴图的颜色权重，照原程序。
		vec3(0.022087, 0.098399, 0.110818),
		vec3(0.011892, 0.095924, 0.089485),
		vec3(0.027636, 0.101689, 0.100326),
		vec3(0.046564, 0.109883, 0.114838),
		vec3(0.064901, 0.117696, 0.097189),
		vec3(0.063761, 0.086895, 0.123646),
		vec3(0.084817, 0.111994, 0.166380),
		vec3(0.097489, 0.154120, 0.091064),
		vec3(0.106152, 0.131144, 0.195191),
		vec3(0.097721, 0.110188, 0.187229),
		vec3(0.133516, 0.138278, 0.148582),
		vec3(0.070006, 0.243332, 0.235792),
		vec3(0.196766, 0.142899, 0.214696),
		vec3(0.047281, 0.315338, 0.321970),
		vec3(0.204675, 0.390010, 0.302066),
		vec3(0.080955, 0.314821, 0.661491));
	vec3 color = textureProj(texSampler, portalCoord).rgb * COLORS[0]; // 第一层。
	for (int i = 0; i < 16; i++){ // 逐层叠加。
		color += textureProj(texSampler, portalCoord * end_portal_layer(float(i + 1))).rgb * COLORS[i]; // 叠上其余各层。
	}
	return color; // 交回叠加后的底色。
}
#endif // OMNI_EFFECT_ENTITY_ENTITY_INCLUDED
