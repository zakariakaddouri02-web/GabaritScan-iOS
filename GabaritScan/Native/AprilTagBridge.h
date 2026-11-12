// AprilTagBridge.h
// Header ObjC exposé à Swift via le Bridging Header.
// Wrappé autour de la bibliothèque C apriltag (tag36h11).

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Un seul tag détecté, avec sa pose estimée.
@interface TagDetectionObjC : NSObject

@property (nonatomic) NSInteger tagId;

/// Coins détectés (8 floats : x0,y0, x1,y1, x2,y2, x3,y3)
@property (nonatomic, strong) NSArray<NSNumber *> *corners;

/// Vecteur de Rodrigues (3 floats)
@property (nonatomic, strong) NSArray<NSNumber *> *rvec;

/// Translation en mm (3 floats)
@property (nonatomic, strong) NSArray<NSNumber *> *tvec;

@property (nonatomic) float reprojectionError;
@property (nonatomic) float azimuthDeg;
@property (nonatomic) float elevationDeg;
@property (nonatomic) float distanceMm;

@end


/// Détecteur AprilTag — wrappé autour d'apriltag.h (C).
@interface AprilTagDetectorObjC : NSObject

/// @param tagFamily  0 = tag36h11
/// @param tagSizeMm  Taille réelle du tag en mm (côté externe)
- (instancetype)initWithTagFamily:(NSInteger)tagFamily
                        tagSizeMm:(float)tagSizeMm;

/// Détecter les tags dans un buffer Y (plan luminance CVPixelBuffer).
/// @param yData      Pointeur vers le plan Y (CVPixelBufferGetBaseAddressOfPlane)
/// @param rowStride  Pas de ligne en octets
/// @param width      Largeur en pixels
/// @param height     Hauteur en pixels
/// @param fx fy cx cy  Intrinsèques caméra
- (NSArray<TagDetectionObjC *> *)detectInYData:(const uint8_t *)yData
                                      rowStride:(size_t)rowStride
                                          width:(size_t)width
                                         height:(size_t)height
                                             fx:(float)fx fy:(float)fy
                                             cx:(float)cx cy:(float)cy;

- (void)dealloc;

@end

NS_ASSUME_NONNULL_END
