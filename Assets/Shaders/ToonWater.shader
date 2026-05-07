Shader "Roystan/Toon/Water"
{
    Properties
    {	
        _DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)
        _DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)
        _DepthMaxDistance("Depth Maximum Distance", Float) = 1
        _SurfaceNoise("Surface Noise", 2D) = "white" {}
        //泡沫量阈值
        _SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777
        //控制海岸线的课件深度（主要用于计算泡沫的）
        _FoamMaxDistance("Foam Maximum Distance", Range(0, 1)) = 0.4
        _FoamMinDistance("Foam Minimum Distance", Range(0, 1)) = 0.04
        _SurfaceNoiseScroll("Surface Noise Scroll Amount", Vector) = (0.03, 0.03, 0, 0)
        //扭曲纹理
        _SurfaceDistortion("Surface Distortion", 2D) = "white" {}	
        _SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27
        _FoamColor("Foam Color", Color) = (1,1,1,1)
    }
    SubShader
    {

        Tags
        {
        	"Queue" = "Transparent"
        }

        Pass
        {

            //水体透明效果
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

			CGPROGRAM

            //设置一个较小的数用来决定平滑边界的大小
            //设置小一点才能精确找到边界进行平滑，不然平滑范围太大会很奇怪
            #define SMOOTHSTEP_AA 0.02

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            float4 alphaBlend(float4 top, float4 bottom)
            {
	            float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
	            float alpha = top.a + bottom.a * (1 - top.a);

	            return float4(color, alpha);
            }

            struct appdata
            {
                float4 vertex : POSITION;
                //噪声纹理uv
                float4 uv : TEXCOORD0;
                float3 normal : NORMAL;

            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 screenPosition : TEXCOORD2;
                float2 noiseUV : TEXCOORD0;
                float2 distortUV : TEXCOORD1;
                float3 viewNormal : NORMAL;
            };

            //直接把需要用到的属性放在对应着色器上方，这样寻找属性会好找
            sampler2D _SurfaceNoise;
            float4 _SurfaceNoise_ST;

            sampler2D _SurfaceDistortion;
            float4 _SurfaceDistortion_ST;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);

                o.screenPosition = ComputeScreenPos(o.vertex);

                o.noiseUV = TRANSFORM_TEX(v.uv, _SurfaceNoise);

                o.distortUV = TRANSFORM_TEX(v.uv, _SurfaceDistortion);

                o.viewNormal = COMPUTE_VIEW_NORMAL;

                return o;
            }

            float4 _DepthGradientShallow;
            float4 _DepthGradientDeep;
            
            float _DepthMaxDistance;

            //_CameraDepthTexture 是 Unity 内置的全局纹理，
            //而非自定义属性（所以不需要也不能在Properties中定义）
            sampler2D _CameraDepthTexture;
            float _SurfaceNoiseCutoff;
            float _FoamMaxDistance;
            float _FoamMinDistance;
            float2 _SurfaceNoiseScroll;
            float _SurfaceDistortionAmount;
            sampler2D _CameraNormalsTexture;
            float4 _FoamColor;

            float4 frag (v2f i) : SV_Target
            {
                
                float existingDepth01 = tex2Dproj(_CameraDepthTexture,
                    UNITY_PROJ_COORD(i.screenPosition)).r;
                float existingDepthLinear = LinearEyeDepth(existingDepth01);
                
                //计算深度差
                float depthDifference = existingDepthLinear - i.screenPosition.w;

                float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);

                //利用投影纹理采样函数得到屏幕中的法线
                //UNITY_PROJ_COORD：将屏幕坐标转换为投影纹理采样所需的坐标
                //tex2Dproj()：投影纹理采样函数
                float3 existingNormal = tex2Dproj(_CameraNormalsTexture, UNITY_PROJ_COORD(i.screenPosition));

                float3 normalDot = saturate(dot(existingNormal, i.viewNormal));

                float foamDistance = lerp(_FoamMaxDistance, _FoamMinDistance, normalDot);

                //泡沫效果判断逻辑
                //saturate：强制把计算结果限制在 0~1 之间（小于 0 取 0，大于 1 取 1）
                //在浅水区的时候缩小判断阈值，在深水区取1，阈值不变
                float foamDepthDifference01 = saturate(depthDifference / foamDistance);
                float surfaceNoiseCutoff = foamDepthDifference01 * _SurfaceNoiseCutoff;

                //将扭曲纹理提取的
                //因为颜色的取值在0 - 1，所以我们想要的是一个二维向量，所以把他进行*2-1，取值改变到-1 - 1之间
                float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;

                //偏移uv采样来噪声实现动画效果
                //不停变换噪声纹理的uv位置，来让采样点采样到不同位置的噪声纹理的纹素来实现水体滚动动画效果
                //再加上扭曲纹理的偏移
                float2 noiseUV = float2((i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x) + distortSample.x, 
                (i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y) + distortSample.y);

                float surfaceNoiseSample = tex2D(_SurfaceNoise, noiseUV).r;

                //利用阈值指定泡沫量的多少
                //smoothstep用于平滑泡沫效果的边缘
                float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, 
                    surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

                float4 surfaceNoiseColor = _FoamColor;
                surfaceNoiseColor.a *= surfaceNoise;

				return alphaBlend(surfaceNoiseColor, waterColor);
            }
            ENDCG
        }
    }
}