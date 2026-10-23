/*
材质与视差的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/ground/material.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/ground/material.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_GROUND_MATERIAL_INCLUDED
#define OMNI_EFFECT_GROUND_MATERIAL_INCLUDED
// @effect {"label":{"zh_cn":"材质与视差","en_us":"Textures & parallax"}}
// @option {"label":{"zh_cn":"方块纹理分辨率","en_us":"Block Texture Resolution"},"description":{"zh_cn":"必须等于资源包方块贴图的分辨率，零表示自动。错误的值会让方块视差错位。","en_us":"Must match the resource pack block texture resolution; zero means auto. A wrong value breaks parallax."}}
#define OMNI_TEXTURE_RESOLUTION 0 // [0 1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"实体纹理分辨率","en_us":"Entity Texture Resolution"},"description":{"zh_cn":"实体视差用的纹理分辨率，必须与资源包一致，否则实体会错位。","en_us":"Texture resolution for entity parallax; must match the pack or entities break."}}
#define OMNI_ENTITIES_TEXTURE_RESOLUTION 16 // [1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"各向异性过滤","en_us":"Anisotropic Filtering"},"description":{"zh_cn":"让倾斜的表面更清晰；开启视差时会被禁用。","en_us":"Sharper textures on tilted surfaces; disabled while parallax is on."},"values":{"0":{"zh_cn":"关","en_us":"off"},"2":{"zh_cn":"2x","en_us":"2x"},"4":{"zh_cn":"4x","en_us":"4x"},"8":{"zh_cn":"8x","en_us":"8x"},"16":{"zh_cn":"16x","en_us":"16x"}}}
#define OMNI_ANISOTROPIC_FILTERING_QUALITY 4 // [0 2 4 8 16]
// @option {"label":{"zh_cn":"法线高光也过滤","en_us":"Filter Normal & Specular"},"description":{"zh_cn":"把各向异性过滤也用在法线与高光贴图上，代价略高但更清晰。","en_us":"Applies anisotropic filtering to the normal and specular maps too."}}
//#define OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR
// @option {"label":{"zh_cn":"实体凹凸","en_us":"Entity Parallax"},"description":{"zh_cn":"给实体也做视差；需要先正确设置实体纹理分辨率。","en_us":"Enables parallax on entities; set the entity texture resolution first."}}
#define OMNI_ENTITIES_PARALLAX 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸模式","en_us":"Parallax Mode"},"description":{"zh_cn":"关、锐利或平滑；锐利保持像素外观，平滑更少锯齿。","en_us":"Off, Sharp or Smooth; Sharp keeps the pixel look, Smooth has fewer artifacts."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"锐利","en_us":"Sharp"},"2":{"zh_cn":"平滑","en_us":"Smooth"}}}
#define OMNI_PARALLAX_MODE 0 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸采样质量","en_us":"Parallax Quality"},"description":{"zh_cn":"锐利模式决定视差范围，平滑模式决定伪影多少，越大越细也越慢。","en_us":"Sharp sets the parallax range, Smooth sets artifact level; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_QUALITY 40 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"凹凸细化步数","en_us":"Parallax Refinements"},"description":{"zh_cn":"平滑视差找到交点后再二分细化的次数，越大边缘越准也越慢。","en_us":"Bisection steps after the parallax hit in Smooth mode; higher is more accurate and slower."},"slider":true}
#define OMNI_PARALLAX_MAX_REFINEMENTS 12 // [0 2 4 6 8 12 16]
// @option {"label":{"zh_cn":"凹凸阴影","en_us":"Parallax Self Shadow"},"description":{"zh_cn":"让视差像素自己也投出阳光阴影，代价很低。","en_us":"Lets parallax pixels cast their own sunlight shadow; cheap."}}
#define OMNI_PARALLAX_SHADOW 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸阴影质量","en_us":"Self Shadow Quality"},"description":{"zh_cn":"视差阴影的采样数，越大越细也越慢。","en_us":"Sample count for the parallax shadow; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_SHADOW_QUALITY 20 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"由凹凸生成法线","en_us":"Parallax Based Normal"},"description":{"zh_cn":"让法线效果与视差一致；平滑模式只对侧面生效。","en_us":"Keeps normals consistent with parallax; Smooth only affects sides."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"仅侧面","en_us":"Side Only"},"2":{"zh_cn":"全部","en_us":"All"}}}
#define OMNI_PARALLAX_BASED_NORMAL 1 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸深度","en_us":"Parallax Depth"},"description":{"zh_cn":"凹凸看起来多深，单位是方块高度。","en_us":"How deep surfaces appear, in block heights."},"slider":true}
#define OMNI_PARALLAX_DEPTH 1.0 // [0.1 0.15 0.2 0.3 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 5.0 7.5 10.0]
// @option {"label":{"zh_cn":"凹凸淡出","en_us":"Parallax Fade"},"description":{"zh_cn":"纹理像素很小时淡出视差，避免远处闪烁；不建议关闭。","en_us":"Fades parallax when texels get tiny, avoiding shimmer; better kept on."}}
#define OMNI_PARALLAX_FADE
// @option {"label":{"zh_cn":"启用 PBR","en_us":"Enable PBR"},"description":{"zh_cn":"使用 labPBR 资源包的表面贴图；关闭后下面这些材质效果全部停用。","en_us":"Uses labPBR surface maps; turning it off disables all the material effects below."}}
#define OMNI_ENABLE_PBR
// @option {"label":{"zh_cn":"PBR 标准类型","en_us":"PBR Format"},"description":{"zh_cn":"资源包用的是 labPBR 还是另一种表面贴图编码。","en_us":"Whether the pack stores labPBR or PTGI surface data."},"values":{"0":{"zh_cn":"labPBR","en_us":"labPBR"},"2":{"zh_cn":"PTGI","en_us":"PTGI"}}}
#define OMNI_TEXTURE_PBR_FORMAT 0 // [0 2]
// @option {"label":{"zh_cn":"限制最大粗糙度","en_us":"Clamp High Roughness"},"description":{"zh_cn":"把高粗糙表面的反射直接屏蔽，省性能。","en_us":"Skips reflections on very rough surfaces to save performance."}}
#define OMNI_ROUGHNESS_CLAMP 1 // [0 1]
// @option {"label":{"zh_cn":"限制方块法线强度","en_us":"Terrain Normal Clamp"},"description":{"zh_cn":"压住方块的极端法线，减少噪点。","en_us":"Limits extreme terrain normals to reduce noise."}}
//#define OMNI_TERRAIN_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制手部法线强度","en_us":"Hand Normal Clamp"},"description":{"zh_cn":"压住手持物的极端法线，减少噪点。","en_us":"Limits extreme hand normals to reduce noise."}}
#define OMNI_HAND_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制实体法线强度","en_us":"Entity Normal Clamp"},"description":{"zh_cn":"压住实体的极端法线，减少噪点。","en_us":"Limits extreme entity normals to reduce noise."}}
#define OMNI_ENTITIES_NORMAL_CLAMP
// --- 资源包法线的整体强度与材质遮蔽：来源 Eclipse `lib/settings.glsl:371-376`、`dimensions/all_solid.fsh:743-752` ---
// 这一组默认不改变画面：材质遮蔽默认关闭，法线倍率默认一倍与资源包期望一致。
// @option {"label":{"zh_cn":"材质缝隙暗部","en_us":"Material Ambient Occlusion"},"description":{"zh_cn":"用资源包法线贴图的蓝通道当作遮蔽，压暗凹陷处的底色；默认关闭，关闭时画面不变。","en_us":"Uses the resource pack normal map's blue channel as occlusion to darken cavities; off by default so the current look is unchanged."}}
#define OMNI_MATERIAL_AO 0 // [0 1]
// @option {"label":{"zh_cn":"表面纹理强度","en_us":"Normal Map Strength"},"description":{"zh_cn":"资源包法线贴图的整体起伏倍率，一倍为资源包期望的原始强度；默认一倍，画面不变。","en_us":"Overall relief multiplier for resource pack normal maps; 1 is the value packs expect; default 1 leaves the current look unchanged."},"slider":true}
#define OMNI_NORMAL_MAP_MULT 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"透光强度","en_us":"SSS Strength"},"description":{"zh_cn":"光照穿透表面的深度倍率，与偏移一起为零时关闭次表面散射。","en_us":"Depth multiplier of light through the surface; with the offset at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"透光偏移","en_us":"SSS Strength Offset"},"description":{"zh_cn":"给穿透深度一个最小值；与倍率一起为零时关闭次表面散射。","en_us":"Minimum value for the light depth; with the multiplier at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH_OFFSET 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"发光曲线","en_us":"Emissive Gamma"},"description":{"zh_cn":"PBR 自发光的亮暗对比强度，越大反差越明显。","en_us":"Contrast curve of PBR emissiveness; higher is more contrast."},"slider":true}
#define OMNI_EMISSIVENESS_GAMMA 2.2 // [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"labPBR 孔隙率","en_us":"labPBR Porosity"},"description":{"zh_cn":"使用资源包里的孔隙率通道，决定表面多容易积水。","en_us":"Uses the porosity channel so the surface can puddle more or less."}}
#define OMNI_TEXTURE_PBR_POROSITY 0 // [0 1]
// @option {"label":{"zh_cn":"默认孔隙率","en_us":"Default Porosity"},"description":{"zh_cn":"资源包不给孔隙率时用的值，越小越不吸水、水洼越明显。","en_us":"Porosity when the pack has none; lower means less absorbent and more puddles."},"slider":true}
#define OMNI_TEXTURE_DEFAULT_POROSITY 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"潮湿反照吸收","en_us":"Wetness Albedo Absorption"},"description":{"zh_cn":"潮湿表面压暗的强度，孔隙率越大越明显。","en_us":"How much wet surfaces darken; stronger with higher porosity."},"slider":true}
#define OMNI_POROSITY_ABSORPTION 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"禁用手部高光","en_us":"Disable Hand Specular"},"description":{"zh_cn":"去掉手持物的高光，解决某些模组下的反射噪点。","en_us":"Removes held item specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_HAND_SPECULAR
// @option {"label":{"zh_cn":"禁用玩家高光","en_us":"Disable Player Specular"},"description":{"zh_cn":"去掉玩家自身的高光，解决某些模组下的反射噪点。","en_us":"Removes the player's own specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_PLAYER_SPECULAR
// @option {"label":{"zh_cn":"实体顶点法线平滑","en_us":"Entity Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供实体顶点切线与法线，代价很低。","en_us":"Provides entity vertex tangents and normals for some mods; cheap."}}
#define OMNI_ENTITIES_VS_TBN 1 // [0 1]
// @option {"label":{"zh_cn":"方块顶点法线平滑","en_us":"Block Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供方块顶点切线与法线，代价很低。","en_us":"Provides block vertex tangents and normals for some mods; cheap."}}
//#define OMNI_TERRAIN_VS_TBN
// @option {"label":{"zh_cn":"未指定方块按植物处理","en_us":"General Grass Fix"},"description":{"zh_cn":"把倾斜的面都当成植物渲染，可能误伤其他方块。","en_us":"Treats tilted faces as plants; may misfire on other blocks."}}
#define OMNI_GENERAL_GRASS_FIX 0 // [0 1]
// @option {"label":{"zh_cn":"白色调试世界","en_us":"White Debug World"},"page":"about","description":{"zh_cn":"把所有几何的底色改写成纯白，用来检查光照与几何；仅供调试。","en_us":"Rewrites every geometry albedo to plain white for checking lighting and geometry; debug only."}}
//#define OMNI_WHITE_DEBUG_WORLD
#endif // 选项层结束
