/*
时间绑定：把加载器的时间输入整理成一个普通结构体，效果只拿数据，不再直接认 `frameTimeCounter` 这类宿主名字。
调用位置：需要动画时间的效果在边界调用 `bind_time()`，再把字段传给 `shaders/gfx/` 的通用函数。
可复制示例：`OmniTime time = bind_time(); float seconds = time.seconds;`
设计原因与取舍：结构体只放纯数值，通用库可以直接接收；
  秒数是累计运行时间，适合循环动画；帧时间是上一帧用时，适合与帧率无关的平滑；
  太阳角度保留加载器原值，零点与零点五分别接近正午与午夜，供昼夜判断使用。
*/
#ifndef OMNI_BIND_TIME_INCLUDED // 只引入一次，避免结构体与函数重复定义。
#define OMNI_BIND_TIME_INCLUDED // 置上标记，后续再次引用直接跳过。
// 时间输入只在加载器声明文件里出现一次。
#include "/common/uniforms.glsl"

struct OmniTime {
	float seconds; // 累计运行秒数，驱动波浪、云和噪声动画。
	float frameTime; // 上一帧用时，单位秒，驱动与帧率无关的平滑。
	int frame; // 帧序号，驱动蓝噪声与抖动序列。
	int day; // 世界天数，季节与月亮周期按它累计。
	float sunAngle; // 太阳角度，零到一表示一整天。
};

// 读取本帧的时间输入；只做打包，不改变任何数值。
OmniTime bind_time(){
	OmniTime time; // 待填充的结构体。
	time.seconds = frameTimeCounter; // 累计秒数，原样交出去。
	time.frameTime = frameTime; // 上一帧用时，原样交出去。
	time.frame = frameCounter; // 帧序号，原样交出去。
	time.day = worldDay; // 世界天数，原样交出去。
	time.sunAngle = sunAngle; // 太阳角度，原样交出去。
	return time; // 返回纯数据，调用方不需要知道来源。
}
#endif // 时间绑定结束。
