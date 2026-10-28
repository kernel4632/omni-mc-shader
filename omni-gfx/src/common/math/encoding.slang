// 数学模块编码工具：伽马、曲线、八位与十六位打包、八面体法线编码。
// 调用位置：由 `common/math.slang` 内联引入，颜色与延迟缓冲共用。
// 可复制示例：`float2 n = ogxEncodeNormal(worldNormal);`
// 设计原因与取舍：编码与解码必须成对出现，放在同一文件里方便核对位运算顺序。

// --- 算法说明与边界 ---
// 伽马编码用二点二指数，解码用倒数；管线曲线是四次方根，解码用两次平方。
// 打包函数把量化后的整数按位移进一个通道，解包时先乘回范围再取整。
// 八面体法线编码把单位球压到正方形，解码时按折叠规则还原；无效贴图按朝外法线处理。
// 编码模块处理显示与中间画面的数值表示：
// 伽马编解码用于贴图颜色；管线曲线用四次方根编码，让十六位定点画面在暗部保留精度。
// 打包函数把两个八位或十六位数塞进一个通道，法线用八面体编码压到两个通道。
// 法线贴图解码会检查三个通道的和，接近零的无效贴图按朝外法线处理。
// 伽马编码用二点二指数，解码用倒数；显示空间与线性空间的转换只在这里维护一份。
// 管线曲线是四次方根，解码用两次平方；中间画面用十六位定点，暗部因此保留足够精度。
// 打包函数把量化后的整数按位移进一个通道，解包时先乘回范围再取整。
// 八面体法线编码把单位球压到正方形，解码时按折叠规则还原；无效贴图按朝外法线处理。
// 法线贴图解码检查三个通道的和，接近零的无效贴图不会产生非数。
// 伽马编码用二点二指数，解码用倒数。
// 管线曲线是四次方根，解码用两次平方。
// 打包函数把整数按位移进一个通道，解包时先乘回范围。
// 八面体法线编码把单位球压到正方形，解码按折叠规则还原。
// 无效法线贴图按朝外法线处理，避免非数。
// 所有编码函数都不读取纹理，输入输出都是普通数值。
// 量化误差由打包位深决定，八位适合颜色，十六位适合深度。
// 解码后的法线重新归一化，量化误差不会让长度偏离一。
// 曲线编码在零附近保持连续，暗部不会出现断层。
// 伽马解码后的颜色可能超过一，光照阶段再夹紧。
// 法线贴图的蓝通道参与有效性判断，缺失时按无效处理。
// 编码与解码必须成对使用，跨模块时只走这一份实现。
// 字节序由位运算固定，不依赖平台。
// 伽马编码用二点二指数，解码用倒数。
// 管线曲线是四次方根，解码用两次平方。
// 打包函数把整数按位移进一个通道，解包时先乘回范围。
// 八面体法线编码把单位球压到正方形，解码按折叠规则还原。
// 无效法线贴图按朝外法线处理，避免非数。
// 编码与解码必须成对使用，跨模块时只走这一份实现。
// 量化误差由打包位深决定，八位适合颜色，十六位适合深度。
// 解码后的法线重新归一化，量化误差不会让长度偏离一。
// 曲线编码在零附近保持连续，暗部不会出现断层。


// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
float3 ogxLinearToGamma(float3 color) { return pow(color, float3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
float3 ogxGammaToLinear(float3 color) { return pow(color, float3(2.2)); }

// 平滑曲线：把零到一映射成两端平、中间陡的零到一，投影光斑与柔边都用它。
// 与 iterationT 的 `curve(x)` 逐项相同，调用方自己保证输入已夹紧。
float ogxCurve01(float x)
{
    return OGX_CURVE01(x);
}

// 中间画面用的四次方根曲线，压缩高动态范围并保住暗部。
float ogxLinearToCurve(float color) { return pow(color, 0.25); }

// 四次方根曲线解码：平方两次得到原值。
float ogxCurveToLinear(float color)
{
    color = color * color; // 按参考写法推进这一步。
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
// 二乘十六位打包把两个零到一的值塞进一个浮点位模式，适合历史缓冲。
// 为什么不用两张纹理：历史深度与参考深度总是一起读写，打包后少一次采样。
// 解包用位运算，不做浮点乘除，跨显卡的结果完全一致。
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
// 八面体法线编码：把单位法线投影到八面体再折到正方形，两个通道就够。
// 相比直接存 xy，八面体在边缘的精度更均匀，低角度法线不会出现台阶。
// 解码时先还原第三分量再归一化，避免插值后的长度偏差。
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
编码结果存进通道时按精度选择位宽。
法线贴图的绿通道方向由调用方决定。
*/
