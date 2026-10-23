/*
生物与玩家的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/entity/entity.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_ENTITY_ENTITY_INCLUDED
#define OMNI_BIND_ENTITY_ENTITY_INCLUDED
#include "/effects/entity/entity.glsl"
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
#endif // OMNI_BIND_ENTITY_ENTITY_INCLUDED
