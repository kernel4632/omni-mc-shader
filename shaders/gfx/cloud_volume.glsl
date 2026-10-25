/*
体积云模块适配层：形状取样、光照步进、沿视线步进与云影已迁到生成库。
调用位置：`rendering/cloud/volumetric.glsl` 引用本文件；
    效果层只把选项、天气与纹理换成参数，算法只在 `omni-gfx/src/cloud_volume.slang` 一份。
可复制示例：`vec4 layer = gfx_cloud_layer(worldDir, media, noise, hitOffset, baseTex, detailTex, curlTex, samples, quality, light);`
设计原因与取舍：结构体字段、函数名、参数顺序与输出参数保持原样，宿主几十处赋值与调用点都不用改；
    三维云噪声与卷曲噪声由调用方传入，库不绑定任何宿主纹理。
*/
#ifndef GFX_CLOUD_VOLUME_INCLUDED
#define GFX_CLOUD_VOLUME_INCLUDED

// 云的基础形状与迁移后的体积步进实现。
// 下面两行只引入依赖，不在这里写任何算式。
#include "/gfx/cloud.glsl"
#include "/omni-gfx/cloud_volume.glsl"

// 旧结构体名接到生成库的类型上，字段名与顺序完全一致。
// 这样宿主逐字段赋值的语句可以原样保留。
#define gfx_cloud_media OgxCumulusMedia

// 三次平滑曲线：把零到一压成两端缓、中间快的过渡。
// 曲线本身只有两项乘法，放在库里与其它云形状共用。
float gfx_cloud_curve(float x){ return ogxCumulusCurve(x); } // 实现在生成库。

// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向加随高度增大的偏移。
// 曲率修正让远处的云跟着地球弧度下沉，否则云层像一块挂在硬板上的贴纸。
vec4 gfx_cloud_set_pos(vec3 marching_pos, gfx_cloud_media media){ return ogxCumulusSetPos(marching_pos, media); } // 实现在生成库。

// 采样云密度：基础形状乘云量得到不透明密度，再叠细节噪声得到碎边。
// 两条返回通道分别给光照与环境消光使用，调用方不能只取其中一条。
vec2 gfx_cloud_sample_density(vec4 cloud_pos, gfx_cloud_media media, bool sample_detail, float coverage,
		sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise, float base_scale, float coverage_offset,
		float detail_scale, float detail_strength){
	return ogxCumulusSampleDensity(cloud_pos, media, sample_detail, coverage, base_noise, detail_noise, curl_noise,
		base_scale, coverage_offset, detail_scale, detail_strength); // 实现在生成库。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
// 光柱只覆盖有限高度，云顶不会被地面附近的闪电整体点亮。
vec3 gfx_cloud_lightning(vec3 relative_pos, gfx_cloud_media media, float light_distance, float falloff){
	return ogxCumulusLightning(relative_pos, media, light_distance, falloff); // 实现在生成库。
}

// 云的光照：沿光方向在云里步进估遮挡，再算直射与环境的合成颜色。
// 五步、步长逐次放大：近处密、远处疏，兼顾体积感与每像素开销。
vec3 gfx_cloud_lighting(vec3 marching_pos, gfx_cloud_media media, vec2 cloud_density, vec4 cloud_pos, float noise,
		float vdotl, float coverage, vec3 world_light, sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise,
		float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	return ogxCumulusLighting(marching_pos, media, cloud_density, cloud_pos, noise, vdotl, coverage, world_light,
		base_noise, detail_noise, curl_noise, base_scale, coverage_offset, detail_scale, detail_strength); // 实现在生成库。
}

// 体积云步进核心：沿视线在云层里步进，返回云的加色项与透过率。
vec4 gfx_cloud_layer(vec3 world_dir, gfx_cloud_media media, vec2 noise, out vec3 hit_offset,
		sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise, float cloud_samples, float cloud_quality,
		vec3 world_light, float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	return ogxCumulusMarch(world_dir, media, noise, hit_offset, base_noise, detail_noise, curl_noise, cloud_samples,
		cloud_quality, world_light, base_scale, coverage_offset, detail_scale, detail_strength); // 实现在生成库。
}

// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
// 两处取较厚者，云影边缘因此不会因为单点采样而碎裂。
float gfx_cloud_shadow_tex(vec2 coord, gfx_cloud_media media, vec3 world_light, float range, sampler3D base_noise,
		sampler2D curl_noise, float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	return ogxCumulusShadowTex(coord, media, world_light, range, base_noise, curl_noise, base_scale, coverage_offset,
		detail_scale, detail_strength); // 实现在生成库。
}

#endif
