/*
调试显示：把数值画成七段数码管方便在屏幕上直接读数，并保留 Omni 自己的调试视图与帧耗时条。
来源：七段数码管照 iterationT `Lib/IndividualFounctions/PrintFloat.glsl` 一比一移植；
  调试视图与帧耗时条是 Omni 原有功能，保留并以中性默认接入，默认不改变玩家画面。
调用位置：
  final 片元阶段需要读数时调用 `PrintFloat`、`PrintUintBinary`，返回的零或一表示该像素是否点亮；
  `debugColor` 覆盖场景颜色，用来查看深度、坐标与中间画面；
  `omniProfiler` 在左下角画一条随帧时间伸缩的横条。
可复制示例：
  `vec3 shown = debugColor(sceneColor, texture(depthtex0, texcoord).r, texcoord);`
  `shown = mix(shown, vec3(0.0), PrintFloat(frameTime * 1000.0, vec2(8.0), 4.0));`
  `shown = omniProfiler(shown, texcoord);`
调用前提（iterationT 原样保留）：`PrintFloat`、`PrintUintBinary` 直接读 `gl_FragCoord`，
  所以只能在片元阶段调用；`debugColor` 读取若干中间画面，调用方要保证它们在当前程序里可见。
设计原因与取舍：
  数码管用一块十五项的查找表描述每段是否点亮，按像素坐标查表，同一个函数既能画整数也能画小数；
  默认关闭全部调试输出，调试代码本身不进入正常画面，避免为了调试改变玩家看到的颜色。
*/
#ifndef OMNI_DEBUG_INCLUDED // 只引入一次，避免函数与常量重复定义。
#define OMNI_DEBUG_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label": {"zh_cn": "调试显示", "en_us": "Debug view"}, "description": {"zh_cn": "0：正常画面；1：原始深度；2：画面坐标；3：几何法线；4：材质参数；5：原版光照。", "en_us": "0: scene; 1: raw depth; 2: screen coordinates; 3: normals; 4: material; 5: vanilla light."}, "values": {"0": {"zh_cn": "正常画面", "en_us": "Scene"}, "1": {"zh_cn": "原始深度", "en_us": "Raw depth"}, "2": {"zh_cn": "画面坐标", "en_us": "Coordinates"}, "3": {"zh_cn": "几何法线", "en_us": "Normals"}, "4": {"zh_cn": "材质参数", "en_us": "Material"}, "5": {"zh_cn": "原版光照", "en_us": "Light data"}}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2 3 4 5]
// @option {"label":{"zh_cn":"性能计时","en_us":"Frame-time bar"},"description":{"zh_cn":"在屏幕左下角画一条横条显示每帧耗时，越长越慢；这是整帧时间，不是逐效果耗时。","en_us":"Draws a bar in the bottom-left showing per-frame time; this is total frame time, not per-effect."}}
//#define OMNI_PROFILER
// 加载器输入提供中间画面与画面尺寸，调试视图按编号读取它们。
#include "/common/uniforms.glsl"

// --- 七段数码管的字模表 ---
// 每一项是一个字节，最低七位分别对应一段笔画是否点亮，位到笔画的对应关系在下面 `SevenSegment` 里说明。
const int numData[15] = int[15](
	0x0000003f, // 数字零的段码。
	0x00000006, // 数字一的段码。
	0x0000005b, // 数字二的段码。
	0x0000004f, // 数字三的段码。
	0x00000066, // 数字四的段码。
	0x0000006d, // 数字五的段码。
	0x0000007d, // 数字六的段码。
	0x00000007, // 数字七的段码。
	0x0000007f, // 数字八的段码。
	0x0000006f, // 数字九的段码。
	0x00000079, // 字母大写的段码，用于科学计数法的十的幂。
	0x00000040, // 负号的段码。
	0x00000037, // 小写字母的段码，用于特殊数值提示。
	0x00000071, // 小写字母的段码，用于特殊数值提示。
	0x00000077); // 小写字母的段码，用于特殊数值提示。

// 判断数码管上一个字符的某个像素点是否点亮。
// 一个字符占四列七行，`pCoord` 是查询点在该字符里的像素坐标，`coordShift` 是查完这一列后指针前进的列数。
// 为什么用查表：每段笔画对应字模里的一位，`switch` 按像素位置挑出该查哪一位，比逐段画线短很多。
bool SevenSegment(int n, inout ivec2 pCoord, int coordShift){
	ivec2 coord = pCoord; // 先保存进入时的坐标，用来判断这个像素落在七行四列里的哪一格。
	pCoord.x += coordShift; // 指针前进，供下一次字符查询接着往右排。
	if (coord.x < 0 || coord.y < 0 || coord.x > 3 || coord.y > 6) return false; // 落在字符外就不点亮。
	bool segments = false; // 默认不点亮。
	int index = coord.x + coord.y * 4; // 把二维格点压成一个编号，方便下面按编号选段。
	switch (index){ // 每个编号对应一段笔画，命中就把该段对应位取出来。
		case 25: case 26: // 底部横段。
			segments = (numData[n] & 0x00000001) > 0; // 取最低位。
		break; // 底部横段结束。
		case 19: case 23: // 右下竖段。
			segments = (numData[n] & 0x00000002) > 0; // 取第二位。
		break; // 右下竖段结束。
		case 7: case 11: // 右上竖段。
			segments = (numData[n] & 0x00000004) > 0; // 取第三位。
		break; // 右上竖段结束。
		case 1: case 2: // 顶部横段。
			segments = (numData[n] & 0x00000008) > 0; // 取第四位。
		break; // 顶部横段结束。
		case 4: case 8: // 左上竖段。
			segments = (numData[n] & 0x00000010) > 0; // 取第五位。
		break; // 左上竖段结束。
		case 16: case 20: // 左下竖段。
			segments = (numData[n] & 0x00000020) > 0; // 取第六位。
		break; // 左下竖段结束。
		case 13: case 14: // 中间横段。
			segments = (numData[n] & 0x00000040) > 0; // 取第七位。
		break; // 中间横段结束。
	}
	return segments; // 返回该像素是否点亮。
}

// 判断小数点位置的像素是否点亮。
// 小数点被当成一个宽度为零的字符，只在一个像素上点亮，所以单独处理。
bool DecimalPoint(int p, inout ivec2 pCoord, int coordShift){
	pCoord.x += coordShift; // 小数点不占宽度，但指针仍要按调用方给的量前进。
	return pCoord == ivec2(p, 0); // 只有落在这个像素上才点亮。
}

// 把一个浮点数画成一串七段数码管，返回该像素是否点亮。
// `pixelShift` 是整串数字相对屏幕原点的像素平移，`scale` 是每个字的放大倍数。
// 为什么分成整数、小数、科学计数三条路：普通数直接逐位画；太大或太小的数改用指数形式，防止位数溢出屏幕。
float PrintFloat(float f, vec2 pixelShift, float scale){
	bool print = false; // 所有笔画只要命中一个就点亮这个像素。
	ivec2 oCoord = ivec2(floor((gl_FragCoord.xy - pixelShift) / scale)); // 屏幕像素换算成数字串坐标。
	if (oCoord.x < -44 || oCoord.x > 25 || oCoord.y < 0 || oCoord.y > 6) return 0.0; // 不在数字串范围内就不点亮。
	ivec2 pCoord = oCoord; // 逐字符推进的查询指针。
	pCoord.x += 5; // 从左边留出一个字符宽度的余量，负号和小数点都在左侧展开。
	uint bitsData = floatBitsToUint(f); // 直接看浮点数的二进制，才能拿到指数和尾数。
	uint S = bitsData >> 31; // 最高位是符号位，用来判断要不要画负号。

	if (isinf(f)){ // 无穷大：画英文字母提示，并按符号决定是否加负号。
		print = print || SevenSegment(13, pCoord, 5); // 特殊数值提示字母。
		print = print || SevenSegment(12, pCoord, 5); // 特殊数值提示字母。
		print = print || SevenSegment(1, pCoord, 5); // 数字一。
		if (S > 0u) print = print || SevenSegment(11, pCoord, 5); // 负数才补负号。
		return float(print); // 返回这个像素是否点亮。
	}else if (isnan(f)){ // 非数：画三个字母提示。
		print = print || SevenSegment(12, pCoord, 5); // 特殊数值提示字母。
		print = print || SevenSegment(14, pCoord, 5); // 特殊数值提示字母。
		print = print || SevenSegment(12, pCoord, 5); // 特殊数值提示字母。
		return float(print); // 返回这个像素是否点亮。
	}

	int E = int((bitsData & 0x7f800000u) >> 23) - 127; // 取出指数并去掉偏移，得到真正的二进制指数。
	int shiftM = 23 - E; // 尾数右移多少位才是整数部分。
	float af = abs(f); // 后面的计算都用绝对值，符号单独处理。

	if (shiftM >= 0 && shiftM <= 32 || f == 0.0){ // 整数位能装进一个三十二位整数时走普通表示。
		uint M = (bitsData & 0x007fffffu) + 0x00800000u; // 补回隐含的最高位，得到完整尾数。
		int whole = int(M >> min(shiftM, 31)); // 右移得到整数部分；移动量夹到三十一避免越界。
		do{ // 从低位往高位逐位画，每画一位指针右移一个字。
			int n = whole % 10; // 当前最低位数字。
			print = print || SevenSegment(n, pCoord, 5); // 画这一位。
			whole = whole / 10; // 去掉这一位。
		}while (whole > 0); // 直到整数部分画完。
		if (S > 0u) print = print || SevenSegment(11, pCoord, 5); // 负数补负号。
		int fraction = int(round(fract(af) * 1e5)); // 取五位小数，四舍五入成整数。
		if (fraction > 0){ // 有小数部分才画小数点和小数位。
			pCoord = oCoord; // 指针回到开头，小数从最左侧重新排。
			print = print || DecimalPoint(-22, pCoord, -22); // 在固定位置画小数点。
			for (int i = 0; i < 5; i++){ // 小数固定画五位。
				int n = fraction % 10; // 当前最低位小数。
				print = print || SevenSegment(n, pCoord, 5); // 画这一位。
				fraction = fraction / 10; // 去掉这一位。
			}
		}
	}else{ // 太大或太小时改用科学计数法。
		int exponent = int(floor(log2(af) / log2(10.0))); // 估算十进制指数。
		float decimalExponent = float(5 - exponent); // 把尾数放大成五位数需要的十的幂。
		if (shiftM > 32){ // 很小的小数，符号和指数的排布要往左多留。
			exponent = -exponent; // 指数取正，负号单独画。
			pCoord.x += exponent > 9 ? -25 : -20; // 指数位数不同，起点位置也不同。
		}else{ // 很大的整数。
			pCoord.x += exponent > 9 ? -20 : -15; // 指数位数不同，起点位置也不同。
		}
		do{ // 逐位画十进制指数。
			int n = exponent % 10; // 当前最低位。
			print = print || SevenSegment(n, pCoord, 5); // 画这一位。
			exponent = exponent / 10; // 去掉这一位。
		}while (exponent > 0); // 直到指数画完。
		if (shiftM > 32) print = print || SevenSegment(11, pCoord, 5); // 小数的指数为负，补负号。
		print = print || SevenSegment(10, pCoord, 10); // 画科学计数法的十的幂的字母。
		if (decimalExponent > 38.0){ // 放大尾数时十的幂可能超出浮点范围，先乘一部分。
			af *= 1e38; // 先乘十的三十八次方。
			decimalExponent -= 38.0; // 剩下的幂继续用。
		}
		int decimal = int(round(af * pow(10.0, decimalExponent))); // 把尾数放大成定点整数。
		for (int i = 0; i < 5; i++){ // 固定画五位有效数字。
			int n = decimal % 10; // 当前最低位。
			print = print || SevenSegment(n, pCoord, 5); // 画这一位。
			decimal = decimal / 10; // 去掉这一位。
		}
		print = print || DecimalPoint(5, pCoord, 2); // 画小数点。
		print = print || SevenSegment(decimal, pCoord, 5); // 画剩下的最高位。
		if (S > 0u) print = print || SevenSegment(11, pCoord, 5); // 负数补负号。
	}
	return float(print); // 返回这个像素是否点亮。
}

// 把一个无符号整数画成三十二位二进制，每位一个数码管，返回该像素是否点亮。
// 排布是每行四位，共八行，方便对着位序排查掩码问题。
float PrintUintBinary(uint u, vec2 pixelShift, float scale){
	bool print = false; // 命中任一笔画就点亮。
	ivec2 oCoord = ivec2(floor((gl_FragCoord.xy - pixelShift) / scale)); // 屏幕像素换算成数字串坐标。
	ivec2 pCoord = oCoord; // 逐位推进的查询指针。
	pCoord.y += -9; // 整体上移，给二进制串腾出位置。
	for (int i = 0; i < 32; i++){ // 三十二个比特各画一位。
		int n = int(u << i >> 31); // 取出第 i 位的零或一。
		print = print || SevenSegment(n, pCoord, -5); // 画这一位，指针向左推进一个字符。
		pCoord.x += i % 4 == 3 ? -5 : 0; // 每满四位换一行。
		if(i == 15) pCoord = oCoord; // 画到第十六位时回到起点，开始第二行。
	}
	return float(print); // 返回这个像素是否点亮。
}

// --- Omni 额外功能：帧耗时条 ---
// 性能计时：加载器只给整帧耗时，没有逐效果计时，所以这里只画一条按耗时长短变化的横条。
// 满格约三十三毫秒；快帧偏绿、慢帧偏红，方便一眼看出卡顿。
vec3 omniProfiler(vec3 color, vec2 coordinates){
#ifdef OMNI_PROFILER // 关闭时不画任何东西。
	vec2 pixel = coordinates*vec2(viewWidth,viewHeight); // 屏幕像素坐标，左下角为原点。
	float filled = clamp(frameTime*1000.0/33.0,0.0,1.0); // 把毫秒换算成零到一的填充比例。
	if (pixel.x < 160.0 && pixel.y < 8.0) { // 只画左下角一小块，不遮挡画面主体。
		float lit = pixel.x/160.0 < filled ? 1.0 : 0.0; // 横条以内是点亮的像素。
		color = mix(vec3(0.04),mix(vec3(0.2,0.9,0.35),vec3(0.95,0.2,0.2),filled),lit); // 快帧偏绿、慢帧偏红。
	}
#endif
	return color; // 未开启时原样返回。
}

// --- Omni 额外功能：选择要观察的中间数据 ---
// 按选项把场景颜色换成深度、坐标或某张中间画面，帮助定位绘制问题。
// 默认零表示不改变玩家画面，所以这个功能是中性接入。
vec3 debugColor(vec3 scene, float depth, vec2 coordinates){
#if OMNI_DEBUG_VIEW == 1 // 深度直接观察实际场景输入。
	return vec3(depth); // 用灰度展示加载器提供的原始深度。
#elif OMNI_DEBUG_VIEW == 2 // 坐标用于定位屏幕取样偏移。
	return vec3(coordinates, 0.0); // 红绿通道分别显示横纵坐标。
#elif OMNI_DEBUG_VIEW == 3 // 法线用于核对几何元数据。
	return texture(colortex1,coordinates).rgb; // 观察实际几何法线编码。
#elif OMNI_DEBUG_VIEW == 4
	return texture(colortex2,coordinates).rgb; // 观察全局光与遮蔽中间结果。
#elif OMNI_DEBUG_VIEW == 5
	return texture(colortex7,coordinates).rgb; // 观察时间抗锯齿历史。
#else
	return scene; // 默认不改变玩家画面。
#endif
}
#endif // 文件守卫结束。
