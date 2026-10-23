/*
受伤、血量与镜头发水的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lens/hurt.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lens/hurt.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LENS_HURT_INCLUDED
#define OMNI_EFFECT_LENS_HURT_INCLUDED
// @effect {"label":{"zh_cn":"受伤、血量与镜头发水","en_us":"Hurt, health & water on camera"}}
// @option {"label":{"zh_cn":"受伤与低血量效果","en_us":"Hurt & low health effect"},"description":{"zh_cn":"受击闪红边、重击整屏染红、低血量染红心跳、死亡整屏暗红；默认关闭，关闭时画面与现在完全一致。来源 Eclipse `lib/gameplay_effects.glsl`。","en_us":"Red edges on a hit, a full-screen red flash on a heavy hit, low-health red heartbeat and a dark red on death; off by default so the default look is unchanged. From Eclipse `lib/gameplay_effects.glsl`."}}
#define OMNI_HURT_EFFECT 0 // [0 1]
// @option {"label":{"zh_cn":"低血量红屏","en_us":"Low health red screen"},"description":{"zh_cn":"血量低时画面边缘染红并随心跳脉冲；默认开启，只有打开上面的总开关才生效。来源 Eclipse `LOW_HEALTH_EFFECT`。","en_us":"Red screen edges with a heartbeat pulse when health is low; on by default, only active when the master effect is enabled. From Eclipse `LOW_HEALTH_EFFECT`."}}
#define OMNI_HURT_LOW_HEALTH 1 // [0 1]
// @option {"label":{"zh_cn":"受击闪红","en_us":"Damage flash"},"description":{"zh_cn":"小伤闪红边（一次掉一点五颗心以上），重击整屏染红（一次掉三点五颗心以上）；默认开启，只有打开总开关才生效。来源 Eclipse `DAMAGE_TAKEN_EFFECT`。","en_us":"Red edges on a small hit (1.5 hearts or more in one go) and a full-screen red flash on a heavy hit (3.5 hearts or more); on by default, only active when the master effect is enabled. From Eclipse `DAMAGE_TAKEN_EFFECT`."}}
#define OMNI_HURT_DAMAGE 1 // [0 1]
// @option {"label":{"zh_cn":"低血量阈值","en_us":"Low health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）开始出现红屏；默认六点零，来源 Eclipse `LOW_HEALTH_EFFECT_START`。","en_us":"Red screen starts below this health in half-hearts; default 6.0, from Eclipse `LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_LOW_HEALTH_START 6.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"危急低血量阈值","en_us":"Critical health threshold"},"slider":true,"description":{"zh_cn":"血量低于这个值（单位半颗心）红屏更强；默认二点零，来源 Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`。","en_us":"The red screen gets stronger below this health in half-hearts; default 2.0, from Eclipse `CRITICALLY_LOW_HEALTH_EFFECT_START`."}}
#define OMNI_HURT_CRITICAL_START 2.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0]
// @option {"label":{"zh_cn":"心跳抖动强度","en_us":"Heartbeat distortion"},"slider":true,"description":{"zh_cn":"低血量时边缘随心跳的抖动量；默认零点二五，来源 Eclipse `MOTION_AMOUNT`。","en_us":"How much the edges wobble with the heartbeat at low health; default 0.25, from Eclipse `MOTION_AMOUNT`."}}
#define OMNI_HURT_MOTION 0.25 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"着火热浪","en_us":"On-fire heat"},"description":{"zh_cn":"身上着火时边缘染橙并随火焰抖动；默认开启，只有打开总开关才生效。来源 Eclipse `ON_FIRE_DISTORT_EFFECT`。","en_us":"Orange edges and a heat wobble while burning; on by default, only active when the master effect is enabled. From Eclipse `ON_FIRE_DISTORT_EFFECT`."}}
#define OMNI_HURT_FIRE 1 // [0 1]
// @option {"label":{"zh_cn":"溺水压暗","en_us":"Drowning darkening"},"description":{"zh_cn":"在水下且血量偏低时整屏偏蓝压暗；默认开启，只有打开总开关才生效。本项目拿不到氧气量，用“在水下且血量低于低血量阈值”近似，来源 Eclipse `DROWNING_EFFECT`。","en_us":"Bluish darkening while underwater at low health; on by default, only active when the master effect is enabled. Air level is unavailable here, so underwater plus low health is used as an approximation. From Eclipse `DROWNING_EFFECT`."}}
#define OMNI_HURT_DROWNING 1 // [0 1]

// @option {"label":{"zh_cn":"镜头发水","en_us":"Water on camera"},"description":{"zh_cn":"下雨、快速移动或在水下时在镜头上挂水珠，水珠把画面轻微抖动并糊开；默认关闭。这是近似：Eclipse 的原始效果依赖跨帧平滑的入水与离水自定义量，本项目拿不到，改用降雨湿润度、相机速度与是否在水下估算。","en_us":"Droplets on the lens that wobble and blur the view when it rains, while moving fast or while the eye is in water; off by default. Approximation: Eclipse drives this from cross-frame smoothed enter and exit water amounts, unavailable here, so wetness, camera speed and the underwater state are combined instead."}}
#define OMNI_WATER_ON_CAMERA 0 // [0 1]
// @option {"label":{"zh_cn":"镜头发水强度","en_us":"Water on camera strength"},"slider":true,"description":{"zh_cn":"水珠折射与糊开的强度；默认一点零，只在上面的镜头发水开启时生效。","en_us":"Strength of the droplet refraction and blur; default 1.0, only used when water on camera is on."}}
#define OMNI_WATER_ON_CAMERA_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#endif // 选项层结束
