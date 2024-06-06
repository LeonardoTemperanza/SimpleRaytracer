
#version 400 core

/////////////////////////////////
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

#define MatType_Matte       0
#define MatType_Reflective  1
#define MatType_Glossy      2
#define MatType_Transparent 3
#define MatType_Translucent 4

struct Material
{
    uint matType;
    
    vec3 emissionScale;
    vec3 colorScale;
    float roughnessScale;
    
    // Texture ids (texture 0 is always white)
    uint emission;
    uint color;
    uint roughness;
};

const Material defaultMat = Material(0, vec3(0.0f), vec3(0.0f), 0.0f, 0, 0, 0);

struct Sphere
{
    vec3 pos;
    float rad;
    Material mat;
};

// Two triangles facing the same direction.
// The first 3 vertices determine the normal direction:
// left hand rule: clockwise -> normal facing away from the screen
struct Quad
{
    // Vertex positions. Triangles are (p0, p1, p2, p1, p3, p2)
    vec3 p[4];
    
    // Texture coords
    vec2 coords[4];
    
    Material mat;
};

const Quad defaultQuad = Quad(vec3[4](vec3(0.0f), vec3(0.0f), vec3(0.0f), vec3(0.0f)), vec2[4](vec2(0.0f), vec2(0.0f), vec2(0.0f), vec2(0.0f)), defaultMat);

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

const RayIntersection defaultRayIntersection = RayIntersection(false, 0.0f);

struct RayQuadResult
{
    int triId;  // -1 if no hit
    float dist;
};

const RayQuadResult defaultRayQuadResult = RayQuadResult(-1, 0.0f);

struct HitInfo
{
    bool hit;
    vec3 pos;
    vec3 normal;
    vec2 texCoords;  // x is u, y is v
    
    Material mat;
};

const HitInfo defaultHitInfo = HitInfo(false, vec3(0.0f), vec3(0.0f), vec2(0.0f), defaultMat);

vec2 Sphere2CubeUV(vec3 origin, float radius, vec3 point)
{
    vec3 p = normalize(point - origin);
    vec2 uv = vec2(0.0f);
    
    vec3 absP = abs(p);
    float maxAxis = max(max(absP.x, absP.y), absP.z);
    if(absP.x >= absP.y && absP.x >= absP.z)  // X faces
    {
        uv.x = p.z * sign(p.x);
        uv.y = p.y;
    }
    else if(absP.y >= absP.x && absP.y >= absP.z)  // Y faces
    {
        uv.x = p.x;
        uv.y = p.z * sign(p.y);
    }
    else // Z faces
    {
        uv.x = -p.x * sign(p.z);
        uv.y = p.y;
    }
    
    uv = 0.5f * (uv / maxAxis + 1.0f);
    return uv;
}

// From:
// https://ceng2.ktu.edu.tr/~cakir/files/grafikler/Texture_Mapping.pdf
vec3 BarycentricCoords(vec3 v0, vec3 v1, vec3 v2, vec3 p)
{
    vec3 v0v1 = v1 - v0;
    vec3 v0v2 = v2 - v0;
    vec3 v0p  = p  - v0;
    float d00 = dot(v0v1, v0v1);
    float d01 = dot(v0v1, v0v2);
    float d11 = dot(v0v2, v0v2);
    float d20 = dot(v0p, v0v1);
    float d21 = dot(v0p, v0v2);
    float denom = d00 * d11 - d01 * d01;
    float v = (d11 * d20 - d01 * d21) / denom;
    float w = (d00 * d21 - d01 * d20) / denom;
    float u = 1.0f - v - w;
    return vec3(u, v, w);
}

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

// From https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/ray-triangle-intersection-geometric-solution.html
RayIntersection RayTriIntersection(Ray ray, vec3 v0, vec3 v1, vec3 v2)
{
    RayIntersection res = defaultRayIntersection;
    
    // Compute the plane's normal
    vec3 v0v1 = v1 - v0;
    vec3 v0v2 = v2 - v0;
    // No need to normalize
    vec3 normal = cross(v0v1, v0v2);
    float area2 = length(normal);
    
    // Step 1: Finding P
    
    // Check if the ray and plane are parallel
    float nDotRayDir = dot(normal, ray.dir);
    if(nDotRayDir >= 0.0f) return res;  // Ray and tri are facing the same way, thus don't show anything
    
    const float epsilon = 0.0001f;
    if(abs(nDotRayDir) < epsilon) // Almost 0
        return res; // They are parallel, so they don't intersect!
    
    // Compute d parameter using equation 2
    float d = -dot(normal, v0);
    
    // Compute t (equation 3)
    float t = -(dot(normal, ray.ori) + d) / nDotRayDir;
    
    // Check if the triangle is behind the ray
    if(t < 0) return res; // The triangle is behind
    
    // Compute the intersection point using equation 1
    vec3 p = ray.ori + t * ray.dir;
    
    // Step 2: Inside-Outside Test
    vec3 c; // Vector perpendicular to triangle's plane
    
    // Edge 0
    vec3 edge0 = v1 - v0; 
    vec3 vp0 = p - v0;
    c = cross(edge0, vp0);
    if(dot(normal, c) < 0) return res; // P is on the right side
    
    // Edge 1
    vec3 edge1 = v2 - v1; 
    vec3 vp1 = p - v1;
    c = cross(edge1, vp1);
    if(dot(normal, c) < 0) return res; // P is on the right side
    
    // Edge 2
    vec3 edge2 = v0 - v2; 
    vec3 vp2 = p - v2;
    c = cross(edge2, vp2);
    if(dot(normal, c) < 0) return res; // P is on the right side
    
    res.dist = t;
    res.hit  = t >= ray.minDist && t <= ray.maxDist;
    return res; // This ray hits the triangle
}

RayQuadResult RayQuadIntersection(Ray ray, Quad quad)
{
    RayQuadResult res = defaultRayQuadResult;
    res.dist = FLT_MAX;
    
    RayIntersection i1 = RayTriIntersection(ray, quad.p[0], quad.p[1], quad.p[2]);
    RayIntersection i2 = RayTriIntersection(ray, quad.p[1], quad.p[3], quad.p[2]);
    
    if(i1.hit && i1.dist < res.dist)
    {
        res.dist  = i1.dist;
        res.triId = 0;
    }
    if(i2.hit && i2.dist < res.dist)
    {
        res.dist  = i2.dist;
        res.triId = 1;
    }
    
    return res;
}

// PCG Random number generator.
// From: www.pcg-random.org and www.shadertoy.com/view/XlGcRh
uint rngState = 0;
uint RandomUInt()
{
    rngState = rngState * 747796405u + 2891336453u;
    uint result = ((rngState >> ((rngState >> 28) + 4u)) ^ rngState) * 277803737u;
    result = (result >> 22) ^ result;
    return result;
}

// From 0 to 1
float RandomFloat()
{
    rngState = rngState * 747796405u + 2891336453u;
    uint result = ((rngState >> ((rngState >> 28) + 4u)) ^ rngState) * 277803737u;
    result = (result >> 22) ^ result;
    return float(result) / 4294967295.0;
}

float RandomFloatNormalDist()
{
    float theta = 2.0f * PI * RandomFloat();
    float rho   = sqrt(-2.0f * log(RandomFloat()));
    return rho * cos(theta);
}

vec2 RandomInCircle()
{
    float angle = RandomFloat() * 2.0f * PI;
    vec2 res = vec2(cos(angle), sin(angle));
    res *= sqrt(RandomFloat());
    return res;
}

// This is the same as sampling a random
// point along a unit sphere. Since the
// multivariate standard normal distribution
// is spherically symmetric, we can just sample
// the normal distribution 3 times to get our
// direction result.
vec3 RandomDirection()
{
    float x = RandomFloatNormalDist();
    float y = RandomFloatNormalDist();
    float z = RandomFloatNormalDist();
    return normalize(vec3(x, y, z));
}

// We can just negate the directions that end up
// on the opposite side
vec3 RandomInHemisphere(vec3 normal)
{
    vec3 dir = RandomDirection();
    return dir * sign(dot(normal, dir));
}

////////////////////////////////////////
// Config

// Rendering
const uint iterations = 30;
const uint NumBounces = 5;
const float fov = 90.0f;
// Materials
//                                   type           emission                   color                   roughness  textures

const Material emissive   = Material(MatType_Matte, vec3(10.0f, 7.0f, 6.0f), vec3(1.0f, 1.0f, 1.0f), 1.0f,      0, 0, 0);
const Material red        = Material(MatType_Matte, vec3(0.0f),                vec3(1.0f, 0.0f, 0.0f), 1.0f,      0, 0, 0);
const Material green      = Material(MatType_Matte, vec3(0.0f),                vec3(0.0f, 1.0f, 0.0f), 1.0f,      0, 0, 0);
const Material blue       = Material(MatType_Matte, vec3(0.0f),                vec3(0.2f, 0.2f, 0.7f), 1.0f,      0, 1, 2);
const Material white      = Material(MatType_Matte, vec3(0.0f),                vec3(1.0f, 1.0f, 1.0f), 1.0f,      0, 0, 0);
const Material grey       = Material(MatType_Matte, vec3(0.0f),                vec3(0.6f, 0.6f, 0.6f), 1.0f,      0, 0, 0);
const Material reflective = Material(MatType_Reflective, vec3(0.0f),           vec3(0.5f, 0.5f, 0.5f), 0.0f,      0, 0, 0);
const Material gReflective = Material(MatType_Reflective, vec3(0.0f),          vec3(0.0f, 0.5f, 0.0f), 0.0f,      0, 0, 0);
const Material wood       = Material(MatType_Matte, vec3(0.0f),                vec3(1.0f, 1.0f, 1.0f), 1.0f,      0, 1, 2);
const Material glass      = Material(MatType_Transparent, vec3(0.0f),          vec3(0.5f, 0.0f, 0.0f), 0.0f,      0, 0, 0);
const Material greenGlass = Material(MatType_Transparent, vec3(0.0f),          vec3(0.0f, 0.5f, 0.0f), 0.0f,      0, 0, 0);
const Material glossy     = Material(MatType_Glossy, vec3(0.0f),               vec3(0.6f, 0.0f, 0.0f), 0.0f,      0, 0, 0);
const Material checkerBoard = Material(MatType_Matte, vec3(0.0f),              vec3(1.0f),             0.0f,      0, 3, 0);
const Material leather    = Material(MatType_Matte, vec3(0.0f),                vec3(1.0f, 1.0f, 1.0f), 1.0f,      0, 4, 5);
const Material metal      = Material(MatType_Matte, vec3(0.0f),                vec3(1.0f, 1.0f, 1.0f), 1.0f,      0, 6, 7);

// Textures (texture arrays are supported in opengl 4.0)
uniform sampler2DArray envMaps;
uniform sampler2DArray textures;

vec3 SampleEnvMap(vec2 coords, uint texId)
{
    return texture(envMaps, vec3(coords, float(texId))).xyz;
}

vec4 SampleTexture(vec2 coords, uint texId)
{
    // Avoiding a texture fetch might be faster
    if(texId == 0) return vec4(1.0f);
    
    return texture(textures, vec3(coords, float(texId)));
}

// Scenes

// First scene showcases textures,
// second scene showcases materials,
// third scene showcases other materials, coverage
// fourth scene is the classic box

uint scene1_envMap = 2;

// Change these values to modify the scenes
Sphere scene1_spheres[] = Sphere[]
//      Origin                      Radius   Material
(Sphere(vec3(-1.2f, 0.0f,    0.5f), 0.5f,    wood),
 Sphere(vec3(0.0f,  0.0f,    0.5f), 0.5f,    leather),
 Sphere(vec3(1.2f,  0.0f,    0.5f), 0.5f,    metal)
 );

Quad scene1_quads[] = Quad[]
// vertex positions,
// texture coordinates,
// material
(Quad(vec3[4](vec3(-10.0f, -0.5f, -10.0f), vec3(-10.0f, -0.5f, 10.0f), vec3(10.0f, -0.5f, -10.0f), vec3(10.0f, -0.5f, 10.0f)),
      vec2[4](vec2(0.0f, 0.0f), vec2(0.0f, 5.0f), vec2(5.0f, 0.0f), vec2(5.0f, 5.0f)),
      wood)
 );

uint scene2_envMap = 4;

// Change these values to modify the scenes
Sphere scene2_spheres[] = Sphere[]
//      Origin                      Radius   Material
(Sphere(vec3(-1.2f, 0.0f,    0.5f), 0.5f,    emissive),
 Sphere(vec3(0.0f,  0.0f,    0.5f), 0.5f,    reflective),
 Sphere(vec3(1.2f,  0.0f,    0.5f), 0.5f,    glass)
 );

Quad scene2_quads[] = Quad[]
// vertex positions,
// texture coordinates,
// material
(Quad(vec3[4](vec3(-10.0f, -0.5f, -10.0f), vec3(-10.0f, -0.5f, 10.0f), vec3(10.0f, -0.5f, -10.0f), vec3(10.0f, -0.5f, 10.0f)),
      vec2[4](vec2(0.0f, 0.0f), vec2(0.0f, 5.0f), vec2(5.0f, 0.0f), vec2(5.0f, 5.0f)),
      wood)
 );

uint scene3_envMap = 0;

// Change these values to modify the scenes
Sphere scene3_spheres[] = Sphere[]
//      Origin                      Radius   Material
(Sphere(vec3(-1.2f, 0.0f,    0.5f), 0.5f,    glass),
 Sphere(vec3(0.0f,  0.0f,    0.5f), 0.5f,    greenGlass),
 Sphere(vec3(1.2f,  0.0f,    0.5f), 0.5f,    glossy),
 Sphere(vec3(1.2f,  0.0f,    -1.0f), 0.5f,    checkerBoard)
 );

Quad scene3_quads[] = Quad[]
// vertex positions,
// texture coordinates,
// material
(Quad(vec3[4](vec3(-10.0f, -0.5f, -10.0f), vec3(-10.0f, -0.5f, 10.0f), vec3(10.0f, -0.5f, -10.0f), vec3(10.0f, -0.5f, 10.0f)),
      vec2[4](vec2(0.0f, 0.0f), vec2(0.0f, 5.0f), vec2(5.0f, 0.0f), vec2(5.0f, 5.0f)),
      wood)
 );

uint scene4_envMap = 0;

// Change these values to modify the scenes
Sphere scene4_spheres[] = Sphere[]
//      Origin                      Radius   Material
(Sphere(vec3(-1.2f, 0.0f,    0.5f), 0.5f,    reflective),
 Sphere(vec3(0.0f,  0.0f,    0.5f), 0.5f,    blue),
 Sphere(vec3(1.2f,  0.0f,    0.5f), 0.5f,    gReflective)
 );

Quad scene4_quads[] = Quad[]
// vertex positions,
// texture coordinates,
// material
(Quad(vec3[4](vec3(-10.0f, -0.5f, -10.0f), vec3(-10.0f, -0.5f, 10.0f), vec3(10.0f, -0.5f, -10.0f), vec3(10.0f, -0.5f, 10.0f)),
      vec2[4](vec2(0.0f, 0.0f), vec2(0.0f, 5.0f), vec2(5.0f, 0.0f), vec2(5.0f, 5.0f)),
      wood)
 );

/////////////////////////////////////////
// Main

in vec2 texCoords;
out vec4 fragColor;

uniform vec2 resolution;
uniform uint frameId;
uniform uint frameAccum;
uniform vec3 cameraPos;
uniform vec2 cameraAngle;
uniform float exposure;

uniform sampler2D previousFrame;

uniform uint scene;

void MatteModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor);
void ReflectiveModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor);
void TransparentModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor);

vec3 CameraFrame2World(vec3 v, float yaw, float pitch);
vec3 SampleEnvMap(vec3 dir, uint mapId);
vec3 SampleSceneEnvMap(vec3 dir, uint scene);
vec3 FresnelSchlick(vec3 color, vec3 normal, vec3 outDir);
float FresnelSchlick(float value, vec3 normal, vec3 outDir);
vec3 SampleMicrofacetNormal(float exponent, vec3 normal, vec2 rnd);

HitInfo RaySceneIntersection(Ray ray);

void main()
{
    float aspectRatio = resolution.x / resolution.y;
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    
    // Make sure we don't reuse pixelIds from one frame to the next
    uint pixelId = uint(gl_FragCoord.y * resolution.x + gl_FragCoord.x);
    uint lastId  = uint(resolution.y * resolution.x + resolution.x);
    // Initialize rngState (our seed)
    rngState = pixelId + (lastId + 1u) * uint(frameId);
    
    // Randomly nudge the coordinate to achieve antialiasing
    vec2 nudgedUv = gl_FragCoord.xy + (RandomFloat() - 0.5f);  // Move 0.5 to the left and right
    nudgedUv = clamp(nudgedUv, vec2(0.0f), resolution.xy);
    nudgedUv /= resolution.xy;
    
    vec2 coord = 2.0f * nudgedUv - 1.0f;
    coord.x *= aspectRatio;
    
    float fov = 90.0f;
    vec3 cameraLookat = normalize(vec3(coord, 1.0f));
    // Rotate to lookAt vector according to camera rotation
    vec3 worldCameraLookat = CameraFrame2World(cameraLookat, cameraAngle.x, cameraAngle.y);
    
    Ray cameraRay = Ray(cameraPos, worldCameraLookat, 0.001f, 10000.0f);
    
    vec3 finalColor = vec3(0.0f);
    for(int j = 0; j < iterations; ++j)
    {
        Ray currentRay = cameraRay;
        
        // Product of all object colors/multiplicative terms that the ray has hit up to now
        vec3 rayColor = vec3(1.0f);
        vec3 incomingLight = vec3(0.0f);
        for(int i = 0; i < NumBounces; ++i)
        {
            vec3 outDir = -currentRay.dir;
            HitInfo hit = RaySceneIntersection(currentRay);
            
            if(!hit.hit)
            {
                incomingLight += SampleSceneEnvMap(currentRay.dir, scene) * rayColor;
                break;
            }
            
            // Ray hit something
            Material mat = hit.mat;
            
            // Choose new ray position and direction
            switch(mat.matType)
            {
                case MatType_Matte:
                {
                    MatteModel(hit, currentRay, incomingLight, rayColor);
                    break;
                }
                case MatType_Reflective:
                {
                    ReflectiveModel(hit, currentRay, incomingLight, rayColor);
                    break;
                }
                case MatType_Transparent:
                {
                    TransparentModel(hit, currentRay, incomingLight, rayColor);
                    break;
                }
                case MatType_Glossy:
                {
                    vec3 matColor = SampleTexture(hit.texCoords, mat.color).xyz * mat.colorScale;
                    
                    float fresnel = FresnelSchlick(0.04f, hit.normal, outDir);
                    if(RandomFloat() < fresnel)  // Rough reflection model
                        ReflectiveModel(hit, currentRay, incomingLight, rayColor);
                    else
                        MatteModel(hit, currentRay, incomingLight, rayColor);
                    
                    break;
                }
            }
        }
        
        finalColor += incomingLight;
    }
    
    finalColor /= float(iterations);
    
    // Progressive rendering
    vec4 curColor = vec4(finalColor, 1.0f);
    if(frameAccum != 0)
    {
        float weight = 1.0f / float(frameAccum);
        vec4 prevColor = texture(previousFrame, texCoords);
        fragColor = prevColor * (1.0f - weight) + curColor * weight;
    }
    else
        fragColor = curColor;
}

void MatteModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor)
{
    Material mat = hit.mat;
    
    vec4 matColor = SampleTexture(hit.texCoords, mat.color) * vec4(mat.colorScale, 1.0f);
    
    currentRay.ori = hit.pos;
    
    if(RandomFloat() > matColor.a)
        return;
    
    currentRay.dir = normalize(hit.normal + RandomDirection());
    
    vec3 emittedLight = SampleTexture(hit.texCoords, mat.emission).xyz * mat.emissionScale;
    
    incomingLight += emittedLight * rayColor;
    rayColor *= matColor.xyz;
}

void ReflectiveModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor)
{
    Material mat = hit.mat;
    vec3 outDir = -currentRay.dir;
    
    vec4 matColor = SampleTexture(hit.texCoords, mat.color) * vec4(mat.colorScale, 1.0f);
    
    currentRay.ori = hit.pos;
    
    if(RandomFloat() > matColor.a)
        return;
    
    float matRoughness = SampleTexture(hit.texCoords, mat.roughness).x * mat.roughnessScale;
    
    vec2 rnd = vec2(RandomFloat(), RandomFloat());
    float exponent = 2.0f / (matRoughness * matRoughness); 
    vec3 microfacetNormal = SampleMicrofacetNormal(exponent, hit.normal, rnd);
    
    vec3 reflection = reflect(currentRay.dir, microfacetNormal);
    currentRay.dir = reflection;
    
    vec3 fresnel = FresnelSchlick(matColor.rgb, microfacetNormal, outDir);
    
    incomingLight += fresnel * rayColor;
    rayColor *= fresnel;
}

void TransparentModel(HitInfo hit, inout Ray currentRay, inout vec3 incomingLight, inout vec3 rayColor)
{
    Material mat  = hit.mat;
    vec3 outDir   = -currentRay.dir;
    vec4 matColor = SampleTexture(hit.texCoords, mat.color) * vec4(mat.colorScale, 1.0f);
    
    currentRay.ori = hit.pos;
    
    if(RandomFloat() > matColor.a)
        return;
    
    float fresnel = FresnelSchlick(0.04f, hit.normal, outDir);
    if(RandomFloat() < fresnel)
    {
        currentRay.dir = reflect(currentRay.dir, hit.normal);
        
        incomingLight += matColor.xyz;
        // Ray color remains unchanged
    }
    else  // Going through the object
    {
        // Ray direction remains unchanged
        
        rayColor *= matColor.xyz;
    }
}

vec3 CameraFrame2World(vec3 v, float yaw, float pitch)
{
    float cosYaw = cos(yaw);
    float sinYaw = sin(yaw);
    float cosPitch = cos(pitch);
    float sinPitch = sin(pitch);
    
    vec3 pitchRotated;
    pitchRotated.x = v.x;
    pitchRotated.y = v.y * cosPitch - v.z * sinPitch;
    pitchRotated.z = v.y * sinPitch + v.z * cosPitch;
    
    // Apply the yaw rotation (around the y-axis)
    vec3 yawPitchRotated;
    yawPitchRotated.x = pitchRotated.x * cosYaw + pitchRotated.z * sinYaw;
    yawPitchRotated.y = pitchRotated.y;
    yawPitchRotated.z = -pitchRotated.x * sinYaw + pitchRotated.z * cosYaw;
    
    return yawPitchRotated;
}

vec3 SampleEnvMap(vec3 dir, uint mapId)
{
    vec2 coords;
    coords.x = (atan(dir.z, dir.x) + PI) / (2*PI);
    coords.y = acos(dir.y) / PI;
    return SampleEnvMap(coords, mapId).xyz;
}

vec3 SampleSceneEnvMap(vec3 dir, uint scene)
{
    switch(scene)
    {
        case 1: return SampleEnvMap(dir, scene1_envMap);
        case 2: return SampleEnvMap(dir, scene2_envMap);
        case 3: return SampleEnvMap(dir, scene3_envMap);
        case 4: return SampleEnvMap(dir, scene4_envMap);
    }
    
    return vec3(0.0f);
}

// From the LittleCG library
// TODO: Seems a little strong... did i make a mistake somewhere?
vec3 FresnelSchlick(vec3 color, vec3 normal, vec3 outDir)
{
    if(color == vec3(0.0f)) return vec3(0.0f);
    
    float cosine = dot(normal, outDir);
    return color + (1.0f - color) * pow(clamp(1.0f - abs(cosine), 0.0f, 1.0f), 5);
}

float FresnelSchlick(float value, vec3 normal, vec3 outDir)
{
    if(value == 0.0f) return 0.0f;
    
    float cosine = dot(normal, outDir);
    return value + (1.0f - value) * pow(clamp(1.0f - abs(cosine), 0.0f, 1.0f), 5);
}

// From the littleCG library
vec3 SampleMicrofacetNormal(float exponent, vec3 normal, vec2 rnd)
{
    float z    = pow(rnd.y, 1.0f / (exponent + 1.0f));
    float r    = sqrt(1.0f - z * z);
    float phi  = 2.0f * PI * rnd.x;
    vec3 local = -vec3(r * cos(phi), r * sin(phi), z);
    local = normalize(local);
    
    // Transform from local to world space
    // https://graphics.pixar.com/library/OrthonormalB/paper.pdf
    mat3 local2World;
    {
        vec3 n  = normalize(normal);
        float a = -1.0f / (sign(n.z) + n.z);
        float b = n.x * n.y * a;
        vec3 x  = vec3(1.0f + sign(n.z) * n.x * n.x * a, sign(n.z) * b, -sign(n.z) * n.x);
        vec3 y  = vec3(b, sign(n.z) + n.y * n.y * a, -n.y);
        local2World = mat3(x, y, n);
    }
    
    return local2World * local;
}

HitInfo RaySceneIntersection(Ray ray)
{
    int objKind = -1;
    int idx     = -1;
    float dist  = FLT_MAX;
    uint triId  = 0; // Can be 0 or 1; only used for quads
    
    // It seems we can't dynamically pick a static array (using generic code) so this will have to do
#define CheckSpheres(sphereArray)                                            \
for(int i = 0; i < sphereArray.length(); ++i)                            \
{                                                                        \
RayIntersection inters = RaySphereIntersection(ray, sphereArray[i]); \
if(inters.hit && inters.dist < dist)                                 \
{                                                                    \
dist = inters.dist;                                              \
idx = i;                                                         \
objKind = ObjKind_Sphere;                                        \
}                                                                    \
}
    //
    
#define CheckQuads(quadArray)                                                \
for(int i = 0; i < quadArray.length(); ++i)                              \
{                                                                        \
RayQuadResult inters = RayQuadIntersection(ray, quadArray[i]);       \
if(inters.triId > -1 && inters.dist < dist)                          \
{                                                                    \
triId = inters.triId;                                            \
dist = inters.dist;                                              \
idx = i;                                                         \
objKind = ObjKind_Quad;                                          \
}                                                                    \
}
    //
    
    switch(scene)
    {
        case 1:
        {
            CheckSpheres(scene1_spheres);
            CheckQuads(scene1_quads);
            break;
        }
        case 2:
        {
            CheckSpheres(scene2_spheres);
            CheckQuads(scene2_quads);
            break;
        }
        case 3:
        {
            CheckSpheres(scene3_spheres);
            CheckQuads(scene3_quads);
            break;
        }
        case 4:
        {
            CheckSpheres(scene4_spheres);
            CheckQuads(scene4_quads);
            break;
        }
    }
#undef CheckSpheres
#undef CheckQuads
    
    if(idx == -1) return defaultHitInfo;
    
    // We hit something
    
    HitInfo res = defaultHitInfo;
    res.hit = true;
    
    if(objKind == ObjKind_Sphere)
    {
        Sphere hitSphere = Sphere(vec3(0.0f), 0.0f, defaultMat);
        switch(scene)
        {
            case 1: hitSphere = scene1_spheres[idx]; break;
            case 2: hitSphere = scene2_spheres[idx]; break;
            case 3: hitSphere = scene3_spheres[idx]; break;
            case 4: hitSphere = scene4_spheres[idx]; break;
        }
        
        vec3 pos = hitSphere.pos;
        res.pos = ray.ori + ray.dir * dist;
        res.normal = normalize(res.pos - pos);
        res.texCoords = Sphere2CubeUV(hitSphere.pos, hitSphere.rad, res.pos);
        res.mat = hitSphere.mat;
    }
    else if(objKind == ObjKind_Quad)
    {
        Quad hitQuad = defaultQuad;
        switch(scene)
        {
            case 1: hitQuad = scene1_quads[idx]; break;
            case 2: hitQuad = scene2_quads[idx]; break;
            case 3: hitQuad = scene3_quads[idx]; break;
            case 4: hitQuad = scene4_quads[idx]; break;
        }
        
        // Get hit triangle
        vec3 tri[3];
        vec2 coords[3];
        if(triId == 0)
        {
            tri = vec3[3](hitQuad.p[0], hitQuad.p[1], hitQuad.p[2]);
            coords = vec2[3](hitQuad.coords[0], hitQuad.coords[1], hitQuad.coords[2]);
        }
        else
        {
            tri = vec3[3](hitQuad.p[1], hitQuad.p[3], hitQuad.p[2]);
            coords = vec2[3](hitQuad.coords[1], hitQuad.coords[3], hitQuad.coords[2]);
        }
        
        res.pos = ray.ori + ray.dir * dist;
        res.normal = normalize(cross(tri[1] - tri[0], tri[2] - tri[0]));
        vec3 uvw = BarycentricCoords(tri[0], tri[1], tri[2], res.pos);
        res.texCoords = uvw.x * coords[0] + uvw.y * coords[1] + uvw.z * coords[2];
        res.mat = hitQuad.mat;
    }
    
    return res;
}
