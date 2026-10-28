/*
效果文件 `effects/shared/fog.glsl`：把雾的密度与散射主体、水面与水下光柱按固定顺序组合起来。
调用位置：合成阶段需要完整雾效时引入本文件；只需要体积雾或地表散射的反射、折射与世界合成可以只引用 `fog_volume.glsl`。
可复制示例：`#include "/effects/shared/fog.glsl"`，随后调用 `VolumetricFog`、`LandAtmosphericScattering`、`UnderwaterVolumetricFog`。
设计原因与取舍：水下体积雾要读水面开关与水雾密度，所以必须先定义雾主体、再引入水面、最后定义水下光柱；
    这三步的顺序就是雾效果的组装约定，放在一个文件里比让每个调用方自己记顺序可靠。
    本文件不定义选项，也不复制任何算法：选项在雾主体与水面主体里，公式在生成的通用库。
*/
#ifndef OMNI_SHARED_FOG_INCLUDED
#define OMNI_SHARED_FOG_INCLUDED
// 雾主体：密度、步进、光照、云影、地表散射与原版雾。
#include "/effects/shared/fog_volume.glsl"
// 水面提供水下雾开关、水雾密度与折射，折射会回调上面已定义的雾函数。
#include "/effects/shared/water.glsl"
// 水下体积雾读水面选项与雾质量，只能放在水面之后。
#include "/effects/shared/fog/underwater_fog.glsl"

#endif // OMNI_SHARED_FOG_INCLUDED
