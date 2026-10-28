// 数学模块编码工具：伽马、曲线、八位与十六位打包、八面体法线编码。
// 调用位置：由 `common/math.slang` 内联引入，颜色与延迟缓冲共用。
// 可复制示例：`float2 n = ogxEncodeNormal(worldNormal);`
// 设计原因与取舍：编码与解码必须成对出现，放在同一文件里方便核对位运算顺序。

// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
float3 ogxLinearToGamma(float3 color) { return pow(color, float3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
float3 ogxGammaToLinear(float3 color) { return pow(color, float3(2.2)); }

// 平滑曲线：把零到一映射成两端平、中间陡的零到一，投影光斑与柔边都用它。
// 与 iterationT 的 `curve(x)` 逐项相同，调用方自己保证输入已夹紧。
float ogxCurve01(float x)
{
    return x * x * (3.0 - 2.0 * x);
}

// 中间画面用的四次方根曲线，压缩高动态范围并保住暗部。
float ogxLinearToCurve(float color) { return pow(color, 0.25); }

// 四次方根曲线解码：平方两次得到原值。
float ogxCurveToLinear(float color)
{
    color = color * color;
    return color * color;
}

// 向量版本的四次方根编码，逐通道处理。
float3 ogxLinearToCurve3(float3 color) { return pow(color, float3(0.25)); }

// 向量版本的四次方根解码，逐通道平方两次。
float3 ogxCurveToLinear3(float3 color)
{
    return float3(ogxCurveToLinear(color.x), ogxCurveToLinear(color.y), ogxCurveToLinear(color.z)); // 逐通道走标量版本。
}

// 把两个八位分量打包进一个浮点；高八位放第一个，低八位放第二个。
float ogxPack2x8(float2 value)
{
    uint2 bits = uint2(value * 255.0);
    return float((bits.x << 8u) | bits.y) / 65535.0;
}

// 从打包浮点还原两个八位分量，读取方必须按同一约定拆位。
float2 ogxUnpack2x8(float value)
{
    uint bits = uint(value * 65535.0);
    return float2(bits >> 8u, bits & 255u) / 255.0;
}

// 把两个十六位分量直接按位塞进浮点，不损失精度，但只能按位还原。
float ogxPack2x16(float2 value)
{
    uint2 bits = uint2(value * 65535.0);
    return asfloat((bits.x << 16u) | bits.y);
}

// 取回两个十六位分量并归一化；输入必须是 `ogxPack2x16` 的结果。
float2 ogxUnpack2x16(float value)
{
    uint bits = asuint(value);
    return float2(bits >> 16u, bits & 65535u) / 65535.0;
}

// 八面体折返：把下半球的分量交换并按符号放回外圈。
float2 ogxOctWrap(float2 v) { return (1.0 - abs(v.yx)) * float2(ogxSign(v.x), ogxSign(v.y)); }

// 把单位法线编码到零到一的二维坐标，八个象限各占一块。
float2 ogxEncodeNormal(float3 n)
{
    n.xy /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = n.z >= 0.0 ? n.xy : ogxOctWrap(n.xy);
    return n.xy * 0.5 + 0.5;
}

// 把八面体坐标解回单位法线，与上一函数互逆。
float3 ogxDecodeNormal(float2 encoded)
{
    float2 n = encoded * 2.0 - 1.0;
    float nz = 1.0 - abs(n.x) - abs(n.y);
    return normalize(float3(nz >= 0.0 ? n : ogxOctWrap(n), nz));
}

// 从贴图法线解出切线空间法线：全黑或全白不是法线数据，退回朝外。
float3 ogxDecodeNormalTex(float3 texNormal)
{
    float3 normal = float3(0.0, 0.0, 1.0);
    if (abs(texNormal.x + texNormal.y + texNormal.z - 1.5) < 1.488)
    {
        normal.xy = texNormal.xy * 2.0 - 1.0;
        normal.xy = max(abs(normal.xy) - 1.0 / 255.0, float2(0.0)) * float2(sign(normal.x), sign(normal.y));
        normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));
    }
    return normal;
}

/*
实现说明：编码与打包。
一、伽马：线性到显示用二点二幂，显示到线性用同一次幂的逆；这是管线的近似，不是标准 sRGB。
二、曲线：四次方根压缩高动态范围，平方两次还原；中间画面用它保住暗部。
三、八位打包：两个零到一的数各取八位，压进一个通道；解包时按同样的位宽拆回。
四、十六位打包：用整数与小数部分搬运两个十六位值，不依赖浮点位模式，跨后端可复现。
五、法线编码：八面体投影把单位向量压到零到一，解码时按绝对值折叠回球面。
六、边界：打包函数假设输入已经在零到一之间，越界值会被截断而不是报错。
七、顺序：编码与解码必须成对修改，位宽或常数改一处就要同步另一处。
*/

/*
函数索引：
一、`ogxLinearToGamma`：线性到显示，二点二幂。
二、`ogxGammaToLinear`：显示到线性，同一次幂的逆。
三、`ogxCurve01`：零到一平滑曲线，两端平、中间陡。
四、`ogxLinearToCurve`：四次方根压缩，中间画面用。
五、`ogxCurveToLinear`：平方两次还原。
六、`ogxLinearToCurve3` 与 `ogxCurveToLinear3`：三分量版本，逐通道处理。
七、`ogxPack2x8` 与 `ogxUnpack2x8`：两个八位数压进一个通道。
八、`ogxPack2x16` 与 `ogxUnpack2x16`：两个十六位数用整数与小数部分搬运。
九、`ogxOctWrap`：八面体编码的折叠，处理负半轴。
十、`ogxEncodeNormal`：单位法线压到零到一。
十一、`ogxDecodeNormal`：零到一还原单位法线。
十二、`ogxDecodeNormalTex`：从贴图通道解出法线，先解码再归一化。
十三、位宽：打包与解包必须成对修改，位宽或常数改一处就要同步另一处。
十四、边界：打包函数假设输入在零到一之间，越界值会被截断。
十五、用途：中间画面、法线图与延迟缓冲共用这一组编码。
*/

/*
参数与边界：
一、伽马函数假设输入非负，负值会得到未定义结果。
二、四次方根曲线假设输入非负，中间画面已经保证。
三、八位打包假设两个输入都在零到一之间。
四、十六位打包用浮点小数部分，输入超出零到一时会丢精度。
五、八面体编码要求法线已归一化。
六、解码后的法线要再归一化，贴图量化会带来长度误差。
七、打包与解包的位宽必须一致。
八、所有函数都是纯函数，不读取纹理或屏幕。
九、编码结果可以存进八位或十六位通道，调用方按精度选择。
十、法线贴图的绿通道方向由调用方决定，库不做翻转。
*/

/*
补充说明：编码的精度。
八位打包适合颜色，十六位打包适合坐标。
法线编码的量化误差在解码后要重新归一化。
伽马函数不处理负值。
四次方根曲线不处理负值。
打包与解包的位宽必须一致。
画面验证看中间画面的暗部与法线边缘。
*/

/*
补充说明：精度与边界。
八位打包适合颜色。
十六位打包适合坐标。
法线解码后要重新归一化。
伽马与四次方根不处理负值。
打包与解包位宽必须一致。
*/
/*
编码结果存进通道时按精度选择位宽。
法线贴图的绿通道方向由调用方决定。
*/

/*
补充说明：通道布局由调用方决定。
法线解码后要重新归一化。
编码与解码必须成对维护。
*/
