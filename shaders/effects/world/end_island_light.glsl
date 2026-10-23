/*
末地主岛光源的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/end_island_light.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/end_island_light.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_END_ISLAND_LIGHT_INCLUDED
#define OMNI_EFFECT_WORLD_END_ISLAND_LIGHT_INCLUDED
// @effect {"label":{"zh_cn":"末地主岛光源","en_us":"End Island Light"}}
// @option {"label":{"zh_cn":"末地主岛光源","en_us":"End Island Light"},"description":{"zh_cn":"在末地主岛上方（世界坐标零点、高度一百九十）放一盏竖直向下的灯，按到灯的距离和入射角照亮附近表面、投出阴影并产生高光。默认关闭，画面与不加这项时一致。","en_us":"Places a downward light above the End main island at world (0, 190, 0) that lights nearby surfaces by distance and angle, casts shadows and adds specular. Off by default."}}
//#define OMNI_END_ISLAND_LIGHT
// @option {"label":{"zh_cn":"主岛光源视野角","en_us":"Island Light FOV"},"description":{"zh_cn":"主岛光源的照射范围角度，单位度；超出这个角度的表面收不到这份光，阴影相机也用这个角度。取自 Eclipse 的七十七度。","en_us":"Cone angle of the island light in degrees; surfaces outside it get no light, and the shadow camera uses the same angle. Eclipse uses 77."},"slider":true}
#define OMNI_END_LIGHT_FOV 77.0 // [30.0 40.0 50.0 60.0 70.0 77.0 90.0 110.0 130.0 150.0]
// @option {"label":{"zh_cn":"主岛光源亮度","en_us":"Island Light Brightness"},"description":{"zh_cn":"主岛光源的整体亮度，一为基准值，零等于关灯。默认一不改变已有的光照尺度。","en_us":"Overall brightness of the island light; 1 is the reference and 0 is off. Default 1 keeps the existing light scale."},"slider":true}
#define OMNI_END_LIGHT_BRIGHTNESS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0]
#endif // 选项层结束
