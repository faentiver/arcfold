// Arcfold GU test: a small PSP program for emulator tests. It drives the
// graphics engine (clear, Gouraud shading, texture sampling, depth test, alpha
// blending, 3D transform) and renders the same image for the same frame number.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <pspdisplay.h>
#include <pspgu.h>
#include <pspgum.h>
#include <pspkernel.h>

PSP_MODULE_INFO("ArcfoldGuTest", PSP_MODULE_USER, 1, 0);
PSP_MAIN_THREAD_ATTR(THREAD_ATTR_USER);

#define BUF_WIDTH 512
#define SCR_WIDTH 480
#define SCR_HEIGHT 272
#define TEX_SIZE 64

struct ColorVertex {
	unsigned int color;
	float x, y, z;
};

struct TexColorVertex {
	float u, v;
	unsigned int color;
	float x, y, z;
};

static unsigned int __attribute__((aligned(16))) list[65536];
static unsigned int __attribute__((aligned(16))) texture[TEX_SIZE * TEX_SIZE];
static struct TexColorVertex __attribute__((aligned(16))) cube[36];
static volatile int running = 1;

static int exit_callback(int arg1, int arg2, void *common) {
	(void)arg1;
	(void)arg2;
	(void)common;
	running = 0;
	return 0;
}

static int callback_thread(SceSize args, void *argp) {
	(void)args;
	(void)argp;
	int id = sceKernelCreateCallback("Exit Callback", exit_callback, NULL);
	sceKernelRegisterExitCallback(id);
	sceKernelSleepThreadCB();
	return 0;
}

static void setup_callbacks(void) {
	int thread = sceKernelCreateThread("callbacks", callback_thread, 0x11, 0xFA0, 0, NULL);
	if (thread >= 0) {
		sceKernelStartThread(thread, 0, NULL);
	}
}

// Colors are ABGR, as the PSP expects them.
static void make_texture(void) {
	for (int y = 0; y < TEX_SIZE; y++) {
		for (int x = 0; x < TEX_SIZE; x++) {
			int light = ((x / 8) + (y / 8)) % 2 == 0;
			texture[y * TEX_SIZE + x] = light ? 0xffffffff : 0xff606060;
		}
	}
}

static void add_face(int face, unsigned int color, const float corners[4][3]) {
	static const float uv[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
	static const int order[6] = {0, 1, 2, 0, 2, 3};
	for (int i = 0; i < 6; i++) {
		struct TexColorVertex *v = &cube[face * 6 + i];
		int c = order[i];
		v->u = uv[c][0];
		v->v = uv[c][1];
		v->color = color;
		v->x = corners[c][0];
		v->y = corners[c][1];
		v->z = corners[c][2];
	}
}

static void make_cube(void) {
	static const float front[4][3] = {{-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1}};
	static const float back[4][3] = {{1, -1, -1}, {-1, -1, -1}, {-1, 1, -1}, {1, 1, -1}};
	static const float left[4][3] = {{-1, -1, -1}, {-1, -1, 1}, {-1, 1, 1}, {-1, 1, -1}};
	static const float right[4][3] = {{1, -1, 1}, {1, -1, -1}, {1, 1, -1}, {1, 1, 1}};
	static const float top[4][3] = {{-1, 1, 1}, {1, 1, 1}, {1, 1, -1}, {-1, 1, -1}};
	static const float bottom[4][3] = {{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, {-1, -1, 1}};
	add_face(0, 0xff3030e0, front);
	add_face(1, 0xff30e030, back);
	add_face(2, 0xffe03030, left);
	add_face(3, 0xff30e0e0, right);
	add_face(4, 0xffe030e0, top);
	add_face(5, 0xffe0e030, bottom);
}

// VRAM offsets, relative to the start of VRAM as sceGuDrawBuffer expects.
static void *vram_offset(unsigned int bytes) {
	static unsigned int next = 0;
	unsigned int offset = next;
	next += bytes;
	return (void *)offset;
}

static void setup_gu(void) {
	void *draw = vram_offset(BUF_WIDTH * SCR_HEIGHT * 4);
	void *disp = vram_offset(BUF_WIDTH * SCR_HEIGHT * 4);
	void *depth = vram_offset(BUF_WIDTH * SCR_HEIGHT * 2);

	sceGuInit();
	sceGuStart(GU_DIRECT, list);
	sceGuDrawBuffer(GU_PSM_8888, draw, BUF_WIDTH);
	sceGuDispBuffer(SCR_WIDTH, SCR_HEIGHT, disp, BUF_WIDTH);
	sceGuDepthBuffer(depth, BUF_WIDTH);
	sceGuOffset(2048 - (SCR_WIDTH / 2), 2048 - (SCR_HEIGHT / 2));
	sceGuViewport(2048, 2048, SCR_WIDTH, SCR_HEIGHT);
	sceGuDepthRange(65535, 0);
	sceGuScissor(0, 0, SCR_WIDTH, SCR_HEIGHT);
	sceGuEnable(GU_SCISSOR_TEST);
	sceGuDepthFunc(GU_GEQUAL);
	sceGuShadeModel(GU_SMOOTH);
	sceGuDisable(GU_CULL_FACE);
	sceGuEnable(GU_CLIP_PLANES);
	sceGuFinish();
	sceGuSync(GU_SYNC_FINISH, GU_SYNC_WHAT_DONE);
	sceDisplayWaitVblankStart();
	sceGuDisplay(GU_TRUE);
}

static void draw_cube(int frame) {
	sceGumMatrixMode(GU_PROJECTION);
	sceGumLoadIdentity();
	sceGumPerspective(70.0f, 16.0f / 9.0f, 0.5f, 100.0f);
	sceGumMatrixMode(GU_VIEW);
	sceGumLoadIdentity();
	sceGumMatrixMode(GU_MODEL);
	sceGumLoadIdentity();
	ScePspFVector3 position = {0.4f, 0.0f, -3.2f};
	ScePspFVector3 rotation = {frame * 0.011f, frame * 0.017f, frame * 0.007f};
	sceGumTranslate(&position);
	sceGumRotateXYZ(&rotation);

	sceGuEnable(GU_DEPTH_TEST);
	sceGuEnable(GU_TEXTURE_2D);
	sceGuTexMode(GU_PSM_8888, 0, 0, 0);
	sceGuTexImage(0, TEX_SIZE, TEX_SIZE, TEX_SIZE, texture);
	sceGuTexFunc(GU_TFX_MODULATE, GU_TCC_RGB);
	sceGuTexFilter(GU_LINEAR, GU_LINEAR);
	sceGuTexScale(1.0f, 1.0f);
	sceGuTexOffset(0.0f, 0.0f);
	sceGumDrawArray(GU_TRIANGLES, GU_TEXTURE_32BITF | GU_COLOR_8888 | GU_VERTEX_32BITF | GU_TRANSFORM_3D,
		36, 0, cube);
	sceGuDisable(GU_TEXTURE_2D);
	sceGuDisable(GU_DEPTH_TEST);
}

static void draw_overlays(int frame) {
	struct ColorVertex *triangle = sceGuGetMemory(3 * sizeof(struct ColorVertex));
	triangle[0] = (struct ColorVertex){0xff0000ff, 24, 248, 0};
	triangle[1] = (struct ColorVertex){0xff00ff00, 136, 248, 0};
	triangle[2] = (struct ColorVertex){0xffff0000, 80, 150, 0};
	sceGuDrawArray(GU_TRIANGLES, GU_COLOR_8888 | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 3, 0, triangle);

	sceGuEnable(GU_BLEND);
	sceGuBlendFunc(GU_ADD, GU_SRC_ALPHA, GU_ONE_MINUS_SRC_ALPHA, 0, 0);
	struct ColorVertex *glass = sceGuGetMemory(2 * sizeof(struct ColorVertex));
	glass[0] = (struct ColorVertex){0x80ffffff, 330, 24, 0};
	glass[1] = (struct ColorVertex){0x80ffffff, 456, 132, 0};
	sceGuDrawArray(GU_SPRITES, GU_COLOR_8888 | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 2, 0, glass);
	sceGuDisable(GU_BLEND);

	// The bar grows by one pixel per frame, so a screenshot shows the frame.
	struct ColorVertex *bar = sceGuGetMemory(2 * sizeof(struct ColorVertex));
	bar[0] = (struct ColorVertex){0xff00ffff, 0, SCR_HEIGHT - 6, 0};
	bar[1] = (struct ColorVertex){0xff00ffff, (float)(frame % SCR_WIDTH), SCR_HEIGHT, 0};
	sceGuDrawArray(GU_SPRITES, GU_COLOR_8888 | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 2, 0, bar);
}

int main(void) {
	setup_callbacks();
	make_texture();
	make_cube();
	sceKernelDcacheWritebackAll();
	setup_gu();

	for (int frame = 0; running; frame++) {
		sceGuStart(GU_DIRECT, list);
		sceGuClearColor(0xff402818);
		sceGuClearDepth(0);
		sceGuClear(GU_COLOR_BUFFER_BIT | GU_DEPTH_BUFFER_BIT);
		draw_cube(frame);
		draw_overlays(frame);
		sceGuFinish();
		sceGuSync(GU_SYNC_FINISH, GU_SYNC_WHAT_DONE);
		sceDisplayWaitVblankStart();
		sceGuSwapBuffers();
	}

	sceGuTerm();
	sceKernelExitGame();
	return 0;
}
