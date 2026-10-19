/*
通用图形库雾模块：粉末效应与多次散射相位。
调用位置：任何需要体积雾或体积云散射的程序；本仓库由 `effects/fog/volumetric.glsl` 转发调用。
可复制示例：
    float p = gfx_fog_phase(VdotL); // 混合前后向的散射相位。
    float w = gfx_powder_effect(absorption, lightingAbsorption, VdotL); // 粉末效应权重。
    gfx_multi_scattering_phases(VdotL, phases); // 四次衰减的相位。
设计原因与取舍：
    只做纯数学，不读取纹理或选项；雾密度、步进与光源方向由调用方负责。
    相位函数复用数学模块里的米氏相位，避免同一公式出现两份。
*/
#ifndef GFX_FOG_INCLUDED
#define GFX_FOG_INCLUDED

#include "/gfx/math.glsl"

// 粉末效应：光穿过薄雾时，背光方向略微增亮，模拟多次散射。
float gfx_powder_effect(float absorption, float lightingAbsorption, float VdotL){
	return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越少效果越强。
}

// 混合前后向的雾相位，让雾在逆光和顺光下都不过分刺眼。
float gfx_fog_phase(float VdotL){
	return gfx_MiePhaseFunction(-0.4, VdotL) * 0.3 + gfx_MiePhaseFunction(0.5, VdotL) * 0.7; // 三成后向、七成前向。
}

// 多次散射相位：把观察角按一半递减，重复四次，写入长度四的数组。
void gfx_multi_scattering_phases(float VdotL, inout float phases[4]){
	float factor = 1.0; // 每一级的夹角倍率。
	for (int i = 0; i < 4; i++, factor *= 0.5){
		phases[i] = gfx_fog_phase(VdotL * factor); // 记录这一级的相位。
	}
}

#endif
