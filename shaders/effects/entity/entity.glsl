/*
生物与玩家的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/entity/entity.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/entity/entity.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
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
#endif // 选项层结束
