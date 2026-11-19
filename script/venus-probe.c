/*
 * Venus capability probe for script/verify-gpu-wiring.sh.
 *
 * Initialises virglrenderer's Venus (Vulkan) backend and queries the Venus
 * capset. Exits 0 only when init succeeds and the capset is non-empty, so a
 * virglrenderer built without -Dvenus=true fails the check.
 *
 * The venus capset id is not part of the public API: virglrenderer's
 * <virglrenderer.h> declares only virgl_renderer_get_cap_set(), and the ids
 * live in the private DRM UAPI header (src/drm/drm-uai/virtgpu_drm.h:
 * VIRTGPU_DRM_CAPSET_VENUS = 4). Mirror that value here.
 */
#define VIRGL_RENDERER_UNSTABLE_APIS 1
#define VENUS_CAPSET_ID 4
#include <stdint.h>
#include <stdio.h>
#include <virglrenderer.h>

int main(void)
{
   struct virgl_renderer_callbacks cbs = {0};
   uint32_t max_ver = 0, max_size = 0;

   cbs.version = 1;
   if (virgl_renderer_init(NULL, VIRGL_RENDERER_NO_VIRGL | VIRGL_RENDERER_VENUS, &cbs) != 0) {
      fprintf(stderr, "virgl_renderer_init(VENUS) failed\n");
      return 1;
   }
   virgl_renderer_get_cap_set(VENUS_CAPSET_ID, &max_ver, &max_size);
   virgl_renderer_cleanup(NULL);
   printf("venus capset version=%u size=%u\n", max_ver, max_size);
   return max_size > 0 ? 0 : 1;
}
