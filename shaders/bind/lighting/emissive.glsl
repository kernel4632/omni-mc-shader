/*
自发光矿石与纹饰的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lighting/emissive.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_LIGHTING_EMISSIVE_INCLUDED
#define OMNI_BIND_LIGHTING_EMISSIVE_INCLUDED
#include "/effects/lighting/emissive.glsl"
/*
自发光矿石与纹饰：按贴图颜色给矿物方块和盔甲纹饰补一份自发光，两项各有一个独立开关。
来源：照 Eclipse `dimensions/all_solid.fsh:331-340`（`getEmission`、`getTrimEmission`）与 `:856-902`
  （`EMISSIVE_ORES`/`EMISSIVE_TRIMS` 分支）移植；矿石方块编号照 Eclipse `block.properties` 的
  `block.502`，盔甲纹饰编号照 Eclipse `item.properties` 的 `item.1026`/`item.1027`，编号已登记在本项目同名文件。
职责：`omniOreEmission` 从底色算出矿石这份发光，`omniTrimEmission` 从底色算出纹饰这份发光；
  两个纯函数只做计算，怎么合并进画面由调用方决定（都是写进五号画面的自发光通道 `specularTex.a`）。
调用位置：
  地形片元：`effects/ground/terrain_surface.glsl` 的 `omniTerrainFragment` 按矿石标记调 `omniOreEmission`；
  实体片元：`rendering/entities.glsl` 按 `currentRenderedItemId` 认出纹饰后调 `omniTrimEmission`。
可复制示例：
  `if (isOre > 0.5) specularTex.a = max(specularTex.a, OMNI_EMISSIVE_ORES_STRENGTH * omniOreEmission(albedo));`
  `float trimGlow = OMNI_EMISSIVE_TRIMS_STRENGTH * omniTrimEmission(albedo);`
调用前提：底色 `albedo` 是已经乘过顶点色的贴图色；`common/math.glsl` 已提供 `omniRgbToHsv`。
关键设计原因与取舍：
  Eclipse 把矿石与纹饰拆成两个独立开关，各带一个亮度，本文件照搬这两个开关与亮度；
  发光直接写进五号画面的自发光通道，与资源包 labPBR 自发光共用同一通道，所以两者只能取较大者合并：
  这样资源包自带发光的方块不会被压暗，代价是不能完全覆盖资源包的自发光（Eclipse 有「覆盖」第三档，本项没搬）；
  矿石发光看色相是否鲜艳、明度是否够高，纹饰发光只看明度，两者都是 Eclipse 原式；
  默认两个开关都关闭，不改变现有画面；开启后需要同时开启物理光照（PBR），否则合成阶段不会读取这份自发光。
*/


// 颜色转 HSV 的 `omniRgbToHsv` 在共用数学里，先引入。
#include "/common/math.glsl"
// 矿石与纹饰的发光公式放在通用库，这里只传底色。
#include "/gfx/surface.glsl"

// 矿石发光：鲜艳（饱和度够高）又明亮（明度高）的像素才发光，来源 Eclipse `getEmission`。
// 为什么同时看饱和度和明度：矿石底料是灰色石头，只有矿物颗粒又艳又亮，用这两条把颗粒和石底分开。
// 为什么明度取三点五次幂：把灰石底压到几乎不发光，只留最亮的颗粒尖，照 Eclipse 系数。
float omniOreEmission(vec3 albedo){
	return gfx_ore_emission(albedo); // 转发到通用库。
}

// 纹饰发光：只看明度，越亮的纹路越亮，来源 Eclipse `getTrimEmission`。
// 为什么开方：暗一些的纹路也保留一部分发光，整块纹饰不会只有最亮处亮。
float omniTrimEmission(vec3 albedo){
	return gfx_trim_emission(albedo); // 转发到通用库。
}
#endif // OMNI_BIND_LIGHTING_EMISSIVE_INCLUDED
