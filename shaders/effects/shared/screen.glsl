/*
效果文件 `effects/shared/screen.glsl`：保存影响全屏画面的调试开关。
调用位置：调色、泛光与原版雾在计算曝光、光晕和雾色前引入本文件，读取“关闭失明与黑暗校正”。
可复制示例：`#include "/effects/shared/screen.glsl"`，随后按 `OMNI_DISABLE_BLINDNESS_DARKNESS` 分派。
设计原因与取舍：失明与黑暗会同时改变曝光、泛光和原版雾，是跨页面的画面状态；
    开关本身只定义一次，各效果自己引入，避免为了一个调试项去引用整个调色文件。
    真正的调色曲线、曝光统计与光晕算法仍留在各自页面的实现文件里。
*/
#ifndef OMNI_SHARED_SCREEN_INCLUDED
#define OMNI_SHARED_SCREEN_INCLUDED
// @effect {"label":{"zh_cn":"画面调试","en_us":"Screen debug"}}
// @option {"label": {"zh_cn": "关闭失明与黑暗校正", "en_us": "Disable Blindness & Darkness"}, "page": "about", "description": {"zh_cn": "调试开关：忽略失明与黑暗对曝光、泛光和原版雾的影响。","en_us": "Debug switch: ignores blindness and darkness on exposure, bloom and vanilla fog."}}
#define OMNI_DISABLE_BLINDNESS_DARKNESS 0 // [0 1]
#endif // OMNI_SHARED_SCREEN_INCLUDED
