#version 450

// layout (local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout (local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

#include "compiled.glsl"
#include "std/math.glsl"
#include "std/gbuffer.glsl"
#include "std/shadows.glsl"
#include "std/imageatomic.glsl"

uniform vec3 lightPos;
uniform vec3 lightColor;
uniform int lightType;
uniform vec3 lightDir;
uniform vec2 spotData;
#ifndef _NoShadows
uniform int lightShadow;
uniform vec2 lightProj;
uniform float shadowsBias;
uniform mat4 LVP;
#endif

uniform layout(binding = 0, rgba8) readonly image3D voxelsOpac;
uniform layout(binding = 1, r32ui) readonly uimage3D voxelsNor;
// uniform layout(binding = 2, rgba8) writeonly image3D voxels;
uniform layout(binding = 2, r32ui) uimage3D voxels;
#ifndef _NoShadows
uniform layout(binding = 3) sampler2D shadowMap;
uniform layout(binding = 4) samplerCube shadowMapCube;
#endif

void main() {

    vec4 col = imageLoad(voxelsOpac, ivec3(gl_GlobalInvocationID.xyz));
    if (col.a == 0.0) return;

    const vec3 hres = voxelgiResolution / 2;
    vec3 wposition = ((gl_GlobalInvocationID.xyz - hres) / hres) * voxelgiHalfExtents;

    uint unor = imageLoad(voxelsNor, ivec3(gl_GlobalInvocationID.xyz)).r;
    vec3 wnormal = normalize(decNor(unor));

    wposition -= wnormal * 0.01; // Offset

    float visibility;
    vec3 lp = lightPos - wposition;
    vec3 l;
    if (lightType == 0) { l = lightDir; visibility = 1.0; }
    else { l = normalize(lp); visibility = attenuate(distance(wposition, lightPos)); }

    float dotNL = max(dot(wnormal, l), 0.0);
    if (dotNL == 0.0) return;

#ifndef _NoShadows
    if (lightShadow == 1) {
        vec4 lightPosition = LVP * vec4(wposition, 1.0);
        vec3 lPos = lightPosition.xyz / lightPosition.w;
        // if (lightPosition.w > 0.0)
        if (texture(shadowMap, lPos.xy).r < lPos.z - shadowsBias) visibility = 0.0;
        // visibility = shadowTest(shadowMap, lPos, shadowsBias, shadowmapSize);
    }
    else if (lightShadow == 2) visibility *= float(texture(shadowMapCube, -l).r + shadowsBias > lpToDepth(lp, lightProj));
#endif

    if (lightType == 2) {
        float spotEffect = dot(lightDir, l);
        if (spotEffect < spotData.x) {
            visibility *= smoothstep(spotData.y, spotData.x, spotEffect);
        }
    }

    col.rgb *= visibility * lightColor * dotNL;
    col = clamp(col, vec4(0.0), vec4(1.0));
    
    // imageStore(voxels, ivec3(gl_GlobalInvocationID.xyz), col);
    imageAtomicAdd(voxels, ivec3(gl_GlobalInvocationID.xyz), convVec4ToRGBA8(col * 255));
}
