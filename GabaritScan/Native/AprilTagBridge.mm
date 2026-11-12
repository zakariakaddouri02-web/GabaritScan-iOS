// AprilTagBridge.mm
// Implémentation ObjC++ : wrappé autour de la lib C apriltag.
// Même logique solvePnP simplifié que gabaritscan_jni.cpp (Android).
// Phase 2 : remplacer solvePnPSimple par OpenCV solvePnPRansac + IPPE.

#import "AprilTagBridge.h"
#import <math.h>
#import <string.h>

// ── Headers AprilTag (sources C dans Native/apriltag/) ────────────────────────
#include "apriltag/apriltag.h"
#include "apriltag/tag36h11.h"
#include "apriltag/common/zarray.h"
#include "apriltag/common/image_u8.h"

// ── TagDetectionObjC ─────────────────────────────────────────────────────────

@implementation TagDetectionObjC
@end

// ── solvePnP simplifié (même algo que Android) ────────────────────────────────

static float solvePnPSimple(
    const float objectPts[4][3],
    const float imagePts[4][2],
    float fx, float fy, float cx, float cy,
    float rvec[3], float tvec[3])
{
    // Centre image du tag
    float cu = 0, cv = 0;
    for (int i = 0; i < 4; i++) { cu += imagePts[i][0]; cv += imagePts[i][1]; }
    cu /= 4; cv /= 4;

    // Taille apparente moyenne des côtés (pixels)
    float edge_px = 0;
    for (int i = 0; i < 4; i++) {
        int j = (i+1)%4;
        float dx = imagePts[j][0]-imagePts[i][0];
        float dy = imagePts[j][1]-imagePts[i][1];
        edge_px += sqrtf(dx*dx+dy*dy);
    }
    edge_px /= 4.0f;

    float tagSideMm = objectPts[1][0] - objectPts[0][0];
    float tz = fx * tagSideMm / edge_px;
    tvec[0] = (cu - cx) * tz / fx;
    tvec[1] = (cv - cy) * tz / fy;
    tvec[2] = tz;

    // Rotation approx. depuis les directions des côtés dans l'image
    float dx01 = imagePts[1][0]-imagePts[0][0], dy01 = imagePts[1][1]-imagePts[0][1];
    float len01 = sqrtf(dx01*dx01+dy01*dy01);
    float dx03 = imagePts[3][0]-imagePts[0][0], dy03 = imagePts[3][1]-imagePts[0][1];
    float len03 = sqrtf(dx03*dx03+dy03*dy03);

    float R[9] = {
        dx01/len01, dx03/len03, 0,
        dy01/len01, dy03/len03, 0,
        0,          0,          1
    };

    float trace = R[0]+R[4]+R[8];
    float angle = acosf(fmaxf(-1.f, fminf(1.f, (trace-1.f)/2.f)));
    if (fabsf(angle) < 1e-6f) {
        rvec[0] = rvec[1] = rvec[2] = 0;
    } else {
        float s = 1.f/(2.f*sinf(angle));
        rvec[0] = (R[7]-R[5])*s*angle;
        rvec[1] = (R[2]-R[6])*s*angle;
        rvec[2] = (R[3]-R[1])*s*angle;
    }

    // Erreur de reprojection
    float totalErr = 0;
    for (int i = 0; i < 4; i++) {
        float px = R[0]*objectPts[i][0]+R[1]*objectPts[i][1]+tvec[0];
        float py = R[3]*objectPts[i][0]+R[4]*objectPts[i][1]+tvec[1];
        float pz = R[6]*objectPts[i][0]+R[7]*objectPts[i][1]+tvec[2];
        float u = fx*px/pz+cx, v = fy*py/pz+cy;
        float du = u-imagePts[i][0], dv = v-imagePts[i][1];
        totalErr += sqrtf(du*du+dv*dv);
    }
    return totalErr / 4.0f;
}

// ── AprilTagDetectorObjC ──────────────────────────────────────────────────────

@implementation AprilTagDetectorObjC {
    apriltag_detector_t *_detector;
    apriltag_family_t   *_family;
    float                _tagSizeMm;
}

- (instancetype)initWithTagFamily:(NSInteger)tagFamily tagSizeMm:(float)tagSizeMm {
    self = [super init];
    if (self) {
        _tagSizeMm = tagSizeMm;
        _family    = tag36h11_create();
        _detector  = apriltag_detector_create();
        apriltag_detector_add_family(_detector, _family);
        _detector->quad_decimate = 2.0f;
        _detector->quad_sigma    = 0.8f;
        _detector->nthreads      = 4;
        _detector->refine_edges  = 1;
        _detector->debug         = 0;
        NSLog(@"[AprilTag] Detector initialisé tag36h11, taille=%.0f mm", tagSizeMm);
    }
    return self;
}

- (NSArray<TagDetectionObjC *> *)detectInYData:(const uint8_t *)yData
                                      rowStride:(size_t)rowStride
                                          width:(size_t)width
                                         height:(size_t)height
                                             fx:(float)fx fy:(float)fy
                                             cx:(float)cx cy:(float)cy
{
    if (!_detector || !yData) return @[];

    // Copier dans image_u8
    image_u8_t *im = image_u8_create((int)width, (int)height);
    for (int row = 0; row < (int)height; row++) {
        memcpy(im->buf + row * im->stride, yData + row * rowStride, width);
    }

    zarray_t *rawDets = apriltag_detector_detect(_detector, im);
    image_u8_destroy(im);

    NSMutableArray<TagDetectionObjC *> *results = [NSMutableArray array];

    float half = _tagSizeMm / 2.0f;
    float objectPts[4][3] = {
        {-half,  half, 0}, { half,  half, 0},
        { half, -half, 0}, {-half, -half, 0}
    };

    for (int i = 0; i < zarray_size(rawDets); i++) {
        apriltag_detection_t *det;
        zarray_get(rawDets, i, &det);

        float imagePts[4][2];
        for (int j = 0; j < 4; j++) {
            imagePts[j][0] = (float)det->p[j][0];
            imagePts[j][1] = (float)det->p[j][1];
        }

        float rvec[3], tvec[3];
        float reproj = solvePnPSimple(objectPts, imagePts, fx, fy, cx, cy, rvec, tvec);

        // Position sphérique
        float tx = tvec[0], ty = tvec[1], tz = tvec[2];
        float dist    = sqrtf(tx*tx+ty*ty+tz*tz);
        float azimuth = atan2f(tx, tz) * 180.0f / M_PI;
        float elev    = atan2f(-ty, sqrtf(tx*tx+tz*tz)) * 180.0f / M_PI;

        TagDetectionObjC *d = [[TagDetectionObjC alloc] init];
        d.tagId = det->id;
        d.corners = @[
            @(imagePts[0][0]), @(imagePts[0][1]),
            @(imagePts[1][0]), @(imagePts[1][1]),
            @(imagePts[2][0]), @(imagePts[2][1]),
            @(imagePts[3][0]), @(imagePts[3][1]),
        ];
        d.rvec = @[@(rvec[0]), @(rvec[1]), @(rvec[2])];
        d.tvec = @[@(tvec[0]), @(tvec[1]), @(tvec[2])];
        d.reprojectionError = reproj;
        d.azimuthDeg   = azimuth;
        d.elevationDeg = elev;
        d.distanceMm   = dist;

        [results addObject:d];
    }

    apriltag_detections_destroy(rawDets);
    return [results copy];
}

- (void)dealloc {
    if (_detector) apriltag_detector_destroy(_detector);
    if (_family)   tag36h11_destroy(_family);
}

@end
