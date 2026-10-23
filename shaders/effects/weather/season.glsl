/*
季节的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/weather/season.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/weather/season.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WEATHER_SEASON_INCLUDED
#define OMNI_EFFECT_WEATHER_SEASON_INCLUDED
// @effect {"label":{"zh_cn":"季节","en_us":"Seasons"}}
// @option {"label":{"zh_cn":"开关","en_us":"Seasons"},"description":{"zh_cn":"草地、树叶和藤蔓的颜色随游戏天数缓慢变化；默认关闭，不影响默认画面。","en_us":"Grass, leaf and vine colour shifts with the in-game day count; off by default so the default look is unchanged."}}
#define OMNI_SEASONS 0 // [0 1]
// @option {"label":{"zh_cn":"颜色","en_us":"Season Colour"},"description":{"zh_cn":"正值偏暖偏秋黄，负值偏冷偏绿。","en_us":"Positive leans warm autumn-yellow, negative leans cool green."},"slider":true}
#define OMNI_SEASON_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
#endif // 选项层结束
