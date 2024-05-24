
#include "assert.h"
#include "stdbool.h"
#include "stdio.h"
#include "stdint.h"
#include "math.h"

// Unity build
#include "glad.c"
#include "GLFW/glfw3.h"

#define Deg2Rad 0.017453292

float fullScreenQuad[] =
{
    // Vertices         // Texture Coords
    -1.0f, 1.0f,  0.0f, 0.0f, 1.0f,
    1.0f,  1.0f,  0.0f, 1.0f, 1.0f,
    -1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
    -1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
    1.0f,  1.0f,  0.0f, 1.0f, 1.0f,
    1.0f,  -1.0f, 0.0f, 1.0f, 0.0f
};

char* vertexShaderSrc = "#version 400 core\n"
"in vec3 pos;\n"
"in vec2 inTexCoords;\n"
"out vec2 texCoords;\n"
"void main()\n"
"{\n"
"gl_Position = vec4(pos, 1.0f);\n"
"texCoords = inTexCoords;\n"
"}\n";

char* tex2ScreenShaderSrc = "#version 400 core\n"
"in vec2 texCoords;\n"
"out vec4 fragColor;\n"
"uniform sampler2D tex;\n"
"void main()\n"
"{\n"
"fragColor = texture(tex, texCoords);\n"
"}\n";

char* pathTracerSrcPath = "../../pathtracer.glsl";

struct
{
    uint32_t program;
    uint32_t tex2ScreenProgram;  // For rendering a texture to the screen
    uint32_t vao;
    
    // For progressive rendering
    uint32_t pingPongFbo[2];
    uint32_t pingPongTex[2];
    
    // Uniforms
    uint32_t resolution;
    uint32_t frameId;
    uint32_t accumulate;
    uint32_t frameAccum;
    uint32_t cameraPos;
    uint32_t cameraAngle;
} typedef RenderState;

struct
{
    float x, y, z;
} typedef Vec3;

Vec3 Sum(Vec3 a, Vec3 b)  { Vec3 res; res.x = a.x+b.x; res.y = a.y+b.y; res.z = a.z+b.z; return res; }
Vec3 Mul(Vec3 a, float f) { Vec3 res = a; res.x *= f; res.y *= f; res.z *= f; return res; }
Vec3 CrossProduct(Vec3 a, Vec3 b)
{
    Vec3 res;
    res.x = a.y * b.z - a.z * b.y;
    res.y = a.z * b.x - a.x * b.z;
    res.z = a.x * b.y - a.y * b.x;
    return res;
}

struct
{
    float x, y;
} typedef Vec2;

struct
{
    Vec2 mouseDelta;
    bool rightClick;
    bool pressedW, pressedA, pressedS, pressedD, pressedE, pressedQ;
} typedef Input;

// Global for simplicity
Input input;

void ErrorCallback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

void MouseButtonCallback(GLFWwindow* window, int button, int action, int mode)
{
    if(button == GLFW_MOUSE_BUTTON_RIGHT)
    {
        if(action == GLFW_PRESS)
            input.rightClick = true;
        else if(action == GLFW_RELEASE)
            input.rightClick = false;
    }
}

void KeyboardButtonCallback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    switch(key)
    {
        default: break;
        case GLFW_KEY_W:
        {
            if(action == GLFW_PRESS)
                input.pressedW = true;
            else if(action == GLFW_RELEASE)
                input.pressedW = false;
            break;
        }
        case GLFW_KEY_A:
        {
            if(action == GLFW_PRESS)
                input.pressedA = true;
            else if(action == GLFW_RELEASE)
                input.pressedA = false;
            break;
        }
        case GLFW_KEY_S:
        {
            if(action == GLFW_PRESS)
                input.pressedS = true;
            else if(action == GLFW_RELEASE)
                input.pressedS = false;
            break;
        }
        case GLFW_KEY_D:
        {
            if(action == GLFW_PRESS)
                input.pressedD = true;
            else if(action == GLFW_RELEASE)
                input.pressedD = false;
            break;
        }
        case GLFW_KEY_E:
        {
            if(action == GLFW_PRESS)
                input.pressedE = true;
            else if(action == GLFW_RELEASE)
                input.pressedE = false;
            break;
        }
        case GLFW_KEY_Q:
        {
            if(action == GLFW_PRESS)
                input.pressedQ = true;
            else if(action == GLFW_RELEASE)
                input.pressedQ = false;
            break;
        }
    }
}

// Returns shader program
RenderState InitRendering();
void ResizeFramebuffers(RenderState* state, int width, int height);

void FirstPersonCamera(Vec3* camPos, Vec2* camRot, float deltaTime);

char* LoadEntireFile(const char* fileName);

int main()
{
    glfwSetErrorCallback(ErrorCallback);
    
    bool ok = glfwInit();
    assert(ok);
    
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);  // Required on macOS
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
    
    GLFWwindow* window = glfwCreateWindow(1200, 1000, "Simple Path Tracer", NULL, NULL);
    assert(window);
    
    // Input callbacks
    glfwSetMouseButtonCallback(window, MouseButtonCallback);
    glfwSetKeyCallback(window, KeyboardButtonCallback);
    
    glfwMakeContextCurrent(window);
    gladLoadGL();
    //gladLoadGLLoader((GLADloadproc)glfwGetProcAddress);
    glfwSwapInterval(1);  // Enable vsync
    
    RenderState renderState = InitRendering();
    
    // Initialize state
    uint32_t accumulate = true;
    uint32_t frameCount = 0;
    uint32_t frameAccum = 0; // Frame counter from start of accumulation
    Vec3 camPos = {0.0f, 0.0f, -10.0f};
    Vec2 camRot = {0};
    
    int prevWidth  = 0;
    int prevHeight = 0;
    Vec2 prevMousePos = {0};
    double prevTime = glfwGetTime();
    bool firstFrame = true;
    while(!glfwWindowShouldClose(window))
    {
        glfwPollEvents();
        
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);
        bool changedSize = (prevWidth != width || prevHeight != height);
        
        float curTime = glfwGetTime();
        float deltaTime = curTime - prevTime;
        prevTime = curTime;
        
        // Get input
        {
            double xPos, yPos;
            glfwGetCursorPos(window, &xPos, &yPos);
            if(firstFrame)
            {
                prevMousePos.x = xPos;
                prevMousePos.y = yPos;
            }
            
            input.mouseDelta.x = (float)xPos - prevMousePos.x;
            input.mouseDelta.y = (float)yPos - prevMousePos.y;
            
            prevMousePos.x = xPos;
            prevMousePos.y = yPos;
        }
        
        // Update state
        {
            if(input.rightClick)
                glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
            else
                glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
            
            FirstPersonCamera(&camPos, &camRot, 1/60.0f);
            
            accumulate = !input.rightClick && !changedSize;
            if(!accumulate) frameAccum = 0;
        }
        
        // Rendering
        {
            // Change framebuffer sizes if needed
            if(changedSize)
                ResizeFramebuffers(&renderState, width, height);
            
            glBindFramebuffer(GL_FRAMEBUFFER, renderState.pingPongFbo[1]);
            
            // Render to framebuffer
            glViewport(0, 0, width, height);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            glUseProgram(renderState.program);
            
            // Set uniforms
            glUniform2f(renderState.resolution, (float)width, (float)height);
            glUniform1ui(renderState.frameId, frameCount);
            glUniform1ui(renderState.accumulate, accumulate);
            glUniform1ui(renderState.frameAccum, frameAccum);
            glUniform3f(renderState.cameraPos, camPos.x, camPos.y, camPos.z);
            glUniform2f(renderState.cameraAngle, camRot.x, camRot.y);
            glBindTexture(GL_TEXTURE_2D, renderState.pingPongTex[0]);
            
            glBindVertexArray(renderState.vao);
            glDrawArrays(GL_TRIANGLES, 0, sizeof(fullScreenQuad) / (sizeof(float) * 3));
            
            // Render produced image to default framebuffer
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            glUseProgram(renderState.tex2ScreenProgram);
            glBindTexture(GL_TEXTURE_2D, renderState.pingPongTex[1]);
            
            glBindVertexArray(renderState.vao);
            glDrawArrays(GL_TRIANGLES, 0, sizeof(fullScreenQuad) / (sizeof(float) * 3));
            
            glfwSwapBuffers(window);
        }
        
        // Swap framebuffer objects for next frame
        uint32_t tmp = renderState.pingPongFbo[0];
        renderState.pingPongFbo[0] = renderState.pingPongFbo[1];
        renderState.pingPongFbo[1] = tmp;
        tmp = renderState.pingPongTex[0];
        renderState.pingPongTex[0] = renderState.pingPongTex[1];
        renderState.pingPongTex[1] = tmp;
        
        prevWidth  = width;
        prevHeight = height;
        ++frameCount;
        ++frameAccum;
        firstFrame = false;
    }
    
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}

RenderState InitRendering()
{
    RenderState res = {0};
    
    // Setup buffers
    uint32_t vbo;
    glGenBuffers(1, &vbo);
    
    glGenVertexArrays(1, &res.vao);
    
    glBindVertexArray(res.vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(fullScreenQuad), fullScreenQuad, GL_STATIC_DRAW);
    
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float))); 
    glEnableVertexAttribArray(1);
    
    // Compile shaders
    uint32_t vertShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertShader, 1, &vertexShaderSrc, NULL);
    glCompileShader(vertShader);
    int success;
    char infoLog[512];
    glGetShaderiv(vertShader, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(vertShader, 512, NULL, infoLog);
        fprintf(stderr, "Vertex shader compilation failed: %s\n", infoLog);
    }
    
    char* fragSrc = LoadEntireFile(pathTracerSrcPath);
    uint32_t fragShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragShader, 1, &fragSrc, NULL);
    glCompileShader(fragShader);
    glGetShaderiv(fragShader, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(fragShader, 512, NULL, infoLog);
        fprintf(stderr, "Fragment shader compilation failed: %s\n", infoLog);
    }
    
    res.program = glCreateProgram();
    glAttachShader(res.program, vertShader);
    glAttachShader(res.program, fragShader);
    glLinkProgram(res.program);
    glGetProgramiv(res.program, GL_LINK_STATUS, &success);
    if(!success)
    {
        glGetProgramInfoLog(res.program, 512, NULL, infoLog);
        fprintf(stderr, "Shader program linking failed: %s\n", infoLog);
    }
    
    // Setup uniforms
    res.resolution  = glGetUniformLocation(res.program, "resolution");
    res.frameId     = glGetUniformLocation(res.program, "frameId");
    res.accumulate  = glGetUniformLocation(res.program, "doAccumulate");
    res.frameAccum  = glGetUniformLocation(res.program, "frameAccum");
    res.cameraPos   = glGetUniformLocation(res.program, "cameraPos");
    res.cameraAngle = glGetUniformLocation(res.program, "cameraAngle");
    
    // Simple texture to screen shader
    uint32_t tex2Screen = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(tex2Screen, 1, &tex2ScreenShaderSrc, NULL);
    glCompileShader(tex2Screen);
    glGetShaderiv(tex2Screen, GL_COMPILE_STATUS, &success);
    if(!success)
    {
        glGetShaderInfoLog(tex2Screen, 512, NULL, infoLog);
        fprintf(stderr, "Simple fragment shader compilation failed: %s\n", infoLog);
    }
    
    res.tex2ScreenProgram = glCreateProgram();
    glAttachShader(res.tex2ScreenProgram, vertShader);
    glAttachShader(res.tex2ScreenProgram, tex2Screen);
    glBindAttribLocation(res.tex2ScreenProgram, 0, "pos");
    glBindAttribLocation(res.tex2ScreenProgram, 1, "inTexCoords");
    glLinkProgram(res.tex2ScreenProgram);
    glGetProgramiv(res.tex2ScreenProgram, GL_LINK_STATUS, &success);
    if(!success)
    {
        glGetProgramInfoLog(res.tex2ScreenProgram, 512, NULL, infoLog);
        fprintf(stderr, "Texture to screen shader program linking failed: %s\n", infoLog);
    }
    
    glDeleteShader(vertShader);
    glDeleteShader(fragShader);
    glDeleteShader(tex2Screen);
    
    return res;
}

void ResizeFramebuffers(RenderState* state, int width, int height)
{
    glDeleteTextures(2, state->pingPongTex);
    glDeleteFramebuffers(2, state->pingPongFbo);
    
    glGenFramebuffers(2, state->pingPongFbo);
    for(int i = 0; i < 2; ++i)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, state->pingPongFbo[i]);
        uint32_t textureColorBuffer;
        glGenTextures(1, &textureColorBuffer);
        glBindTexture(GL_TEXTURE_2D, textureColorBuffer);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textureColorBuffer, 0);
        
        state->pingPongTex[i] = textureColorBuffer;
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        fprintf(stderr, "Failed to create frame buffer object\n");
    }
}

void FirstPersonCamera(Vec3* camPos, Vec2* camRot, float deltaTime)
{
    if(!input.rightClick) return;
    
    const float moveSpeed = 4.0f;
    const float mouseSensitivity = 0.2f * Deg2Rad;  // 0.2f degrees per pixel
    const float maxAngle = 89.0f * Deg2Rad;
    
    // Update rotation
    {
        camRot->x += input.mouseDelta.x * mouseSensitivity;
        camRot->y += input.mouseDelta.y * mouseSensitivity;
        camRot->y = max(min(camRot->y, maxAngle), -maxAngle);
    }
    
    // Update position
    {
        float pitch = camRot->y;
        float yaw   = camRot->x;
        
        Vec3 lookAt =
        {
            sin(yaw) * cos(pitch),
            -sin(pitch),
            cos(yaw) * cos(pitch)
        };
        
        Vec3 up = {0.0f, 1.0f, 0.0f};
        Vec3 right = CrossProduct(up, lookAt);
        
        Vec3 vel = {0};
        vel = Sum(vel, Mul(lookAt, input.pressedW * moveSpeed - input.pressedS * moveSpeed));
        vel = Sum(vel, Mul(right, input.pressedD * moveSpeed - input.pressedA * moveSpeed));
        vel = Sum(vel, Mul(up, input.pressedE * moveSpeed - input.pressedQ * moveSpeed));
        
        *camPos = Sum(*camPos, Mul(vel, deltaTime));
    }
}

char* LoadEntireFile(const char* fileName)
{
    FILE* f = fopen(fileName, "rb");
    if(!f)
    {
        char* res = malloc(1);
        *res = '\0';
        return res;
    }
    
    fseek(f, 0, SEEK_END);
    size_t fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    char* res = malloc(fileSize + 1);
    fread(res, fileSize, 1, f);
    res[fileSize] = '\0';
    
    fclose(f);
    
    return res;
}
