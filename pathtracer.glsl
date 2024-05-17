
// #include is an extension and so is maybe not supported by everyone
// so i'm just putting everything in a single file

#version 400 core

////////////////
// Utils
#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define DBL_MAX 1.7976931348623158e+308
#define DBL_MIN 2.2250738585072014e-308
#define PI      3.1415926

// GLSL doesn't have enums?
#define ObjKind_Sphere 0
#define ObjKind_Quad   1
#define ObjKind_Count  2

struct Material
{
    vec3 color;
    vec3 emissionColor;
    float emissionStrength;
};

struct Sphere
{
    vec3 pos;  // World space
    float rad;
    Material mat;
};

struct Quad
{
    vec3 p0, p1, p2;  // Tri 1
    vec3 p3, p4, p5;  // Tri 2
    
    // Texture coords
    
    Material mat;
};

// Mesh will have a vertex array and an index array

struct Ray
{
    vec3 ori;
    vec3 dir;
    float minDist;
    float maxDist;
};

struct RayIntersection
{
    bool hit;
    float dist;
};

struct HitInfo
{
    bool hit;
    vec3 pos;
    vec3 normal;
    
    Material mat;
};

RayIntersection RaySphereIntersection(Ray ray, Sphere sphere)
{
    vec3 oc = ray.ori - sphere.pos;
    float a = dot(ray.dir, ray.dir);
    float b = 2.0f * dot(oc, ray.dir);
    float c = dot(oc, oc) - sphere.rad * sphere.rad;
    float discriminant = b * b - 4.0f * a * c;
    
    bool intersection = discriminant >= 0.0f;
    float dist = 0.0f;
    if(intersection)
    {
        // Sphere intersections
        float t0 = (-b + sqrt(discriminant)) / (2.0f * a);
        float t1 = (-b - sqrt(discriminant)) / (2.0f * a);
        dist = min(t0, t1) * float(intersection);
        
        // If this intersection is not within the allowed range, then
        // mark it as not intersected
        if(dist < ray.minDist || dist > ray.maxDist) intersection = false;
    }
    
    return RayIntersection(intersection, dist);
}

// PCG Random number generator.
// From: www.pcg-random.org and www.shadertoy.com/view/XlGcRh
uint RandomUInt(inout uint state)
{
    state = state * 747796405u + 2891336453u;
    uint result = ((state >> ((state >> 28) + 4u)) ^ state) * 277803737u;
    result = (result >> 22) ^ result;
    return result;
}

float RandomFloat(inout uint state)
{
    state = state * 747796405u + 2891336453u;
    uint result = ((state >> ((state >> 28) + 4u)) ^ state) * 277803737u;
    result = (result >> 22) ^ result;
    return float(result) / 4294967295.0;
}

float RandomFloatNormalDist(inout uint state)
{
    float theta = 2.0f * PI * RandomFloat(state);
    float rho   = sqrt(-2.0f * log(RandomFloat(state)));
    return rho * cos(theta);
}

vec2 RandomInCircle(inout uint state)
{
    float angle = RandomFloat(state) * 2.0f * PI;
    vec2 res = vec2(cos(angle), sin(angle));
    res *= sqrt(RandomFloat(state));
    return res;
}

// This is the same as sampling a random
// point along a unit sphere. Since the
// multivariate standard normal distribution
// is spherically symmetric, we can just sample
// the normal distribution 3 times to get our
// direction result.
vec3 RandomDirection(inout uint state)
{
    float x = RandomFloatNormalDist(state);
    float y = RandomFloatNormalDist(state);
    float z = RandomFloatNormalDist(state);
    return normalize(vec3(x, y, z));
}

// We can just negate the directions that end up
// on the opposite side
vec3 RandomInHemisphere(vec3 normal, inout uint state)
{
    vec3 dir = RandomDirection(state);
    return dir * sign(dot(normal, dir));
}

////////////////
// Config

// Rendering
#define NumBounces 5
const float fov = 90.0f;

// Materials
const Material zeroMat = Material(vec3(0.0f), vec3(0.0f), 0.0f);
const Material emissive = Material(vec3(1.0f), vec3(1.0f), 10.0f);
const Material red = Material(vec3(1.0f, 0.0f, 0.0f), vec3(0.0f), 0.0f);
const Material green = Material(vec3(0.0f, 1.0f, 0.0f), vec3(0.0f), 0.0f);
const Material blue = Material(vec3(0.0f, 0.0f, 1.0f), vec3(0.0f), 0.0f);
const Material white = Material(vec3(1.0f, 1.0f, 1.0f), vec3(0.0f), 0.0f);

// Scene
// To easily select a scene, change these defines
#define Scene_SphereArray scene0_spheres
#define Scene_QuadArray   scene0_quads
#define Scene_EnvMap      scene0_envmap

// Change these values to modify the scenes
Sphere scene0_spheres[5] = Sphere[]
(Sphere(vec3(-1.2f, 0.0f,    0.5f), 0.5f, red),
 Sphere(vec3(0.0f,  0.0f,    0.5f), 0.5f, green),
 Sphere(vec3(1.2f,  0.0f,    0.5f), 0.5f, blue),
 Sphere(vec3(0.0f,  -100.5f, 0.0f), 100.0f, white),
 Sphere(vec3(100.0f, 60.0f,  -40.0f), 50.0f, emissive));

////////////////
// Main

in vec2 texCoords;
out vec4 fragColor;

uniform vec2 resolution;
uniform uint frameId;
uniform uint doAccumulate;
uniform uint frameAccum;
uniform vec3 cameraPos;
uniform vec2 cameraAngle;

uniform sampler2D previousFrame;

HitInfo RaySceneIntersection(Ray ray)
{
    int objKind = -1;
    int idx     = -1;
    float dist  = FLT_MAX;
    
    for(int i = 0; i < Scene_SphereArray.length(); ++i)
    {
        RayIntersection inters = RaySphereIntersection(ray, Scene_SphereArray[i]);
        if(inters.hit && inters.dist < dist)
        {
            dist = inters.dist;
            idx = i;
            objKind = ObjKind_Sphere;
        }
    }
    
    if(idx == -1) return HitInfo(false, vec3(0.0f), vec3(0.0f), zeroMat);
    
    // We hit something
    
    HitInfo res = HitInfo(false, vec3(0.0f), vec3(0.0f), zeroMat);
    res.hit = true;
    
    if(objKind == ObjKind_Sphere)
    {
        vec3 pos = Scene_SphereArray[idx].pos;
        res.pos = ray.ori + ray.dir * dist;
        res.normal = normalize(res.pos - pos);
        res.mat = Scene_SphereArray[idx].mat;
    }
    else if(objKind == ObjKind_Quad)
    {
        res.hit = false;
    }
    
    return res;
}

void main()
{
    float aspectRatio = resolution.x / resolution.y;
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    
    fragColor = vec4(uv, 1.0f, 1.0f);
    
    // Make sure we don't reuse pixelIds from one frame to the next
    uint pixelId = uint(gl_FragCoord.y * resolution.x + gl_FragCoord.x);
    uint lastId  = uint(resolution.y * resolution.x + resolution.x);
    uint rngState = pixelId + (lastId + 1u) * uint(frameId);
    
    // Randomly nudge the coordinate to achieve antialiasing
    vec2 nudgedUv = gl_FragCoord.xy + RandomInCircle(rngState);
    nudgedUv = clamp(nudgedUv, vec2(0.0f), resolution.xy);
    nudgedUv /= resolution.xy;
    
    vec2 coord = 2.0f * nudgedUv - 1.0f;
    coord.x *= aspectRatio;
    
    float fov = 90.0f;
    vec3 cameraPos = vec3(0.0f, 0.0f, -3.0f);
    
    vec3 cameraLookat = vec3(coord, 1.0f);
    
    Ray cameraRay = Ray(cameraPos, cameraLookat, 0.001f, 10000.0f);
    
    vec3 finalColor = vec3(0.0f);
    const int iters = 10;
    for(int j = 0; j < iters; ++j)
    {
        Ray currentRay = cameraRay;
        vec3 rayColor = vec3(1.0f);
        vec3 incomingLight = vec3(0.0f);
        for(int i = 0; i < NumBounces; ++i)
        {
            HitInfo hit = RaySceneIntersection(currentRay);
            if(!hit.hit)
            {
                incomingLight += vec3(0.4f, 0.8f, 0.9f) * rayColor;
                break;
            }
            
            // Ray hit something
            // Update the ray position and direction
            currentRay.ori = hit.pos;
            
            vec3 cosWeightedRandom = hit.normal + RandomDirection(rngState);
            if(abs(dot(cosWeightedRandom, cosWeightedRandom)) < 0.001f)
                cosWeightedRandom = hit.normal;
            else
                cosWeightedRandom = normalize(cosWeightedRandom);
            
            currentRay.dir = cosWeightedRandom;
            
            Material mat = hit.mat;
            vec3 emittedLight = mat.emissionColor * mat.emissionStrength;
            float lightStrength = dot(hit.normal, currentRay.dir);
            
            incomingLight += emittedLight * rayColor;
            rayColor *= mat.color * lightStrength;
        }
        
        finalColor += incomingLight;
    }
    
    finalColor /= float(iters);
    fragColor = vec4(finalColor, 1.0f);
}