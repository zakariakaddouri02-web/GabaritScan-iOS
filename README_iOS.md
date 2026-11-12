# GabaritScan iOS — Guide Windows → Codemagic → AltServer → iPhone 12 Pro Max

## Workflow complet

```
VS Code (Windows) → GitHub → Codemagic (Mac cloud) → .IPA → AltServer (Windows) → iPhone
```

---

## Étape 1 — Préparer le projet sur Windows

### Installer Git
Télécharger depuis [git-scm.com](https://git-scm.com/download/win)

### Cloner AprilTag C (obligatoire)
```powershell
cd C:\Users\USER\.gemini\antigravity\scratch\GabaritScan-iOS
git clone --depth=1 https://github.com/AprilRobotics/apriltag.git GabaritScan/Native/apriltag
```

### Créer le repo GitHub
```powershell
git init
git add .
git commit -m "feat: GabaritScan iOS MVP Phase 1"
# Créer un repo sur github.com puis :
git remote add origin https://github.com/TON_USERNAME/GabaritScan-iOS.git
git push -u origin main
```

> **Important** : Ajouter dans `.gitignore` :
> ```
> build/
> *.xcuserdata
> DerivedData/
> ```

---

## Étape 2 — Créer le projet Xcode (sur Mac cloud Codemagic ou localement si accès)

> Si tu n'as pas de Mac, Codemagic peut générer le `.xcodeproj` via un script.
> Sinon, utiliser [Xcodeproj gem](https://github.com/CocoaPods/Xcodeproj) pour le créer en ligne de commande.

Structure cible du `.xcodeproj` :
```
GabaritScan.xcodeproj
GabaritScan/
  Sources/
    GabaritScanApp.swift
    Core/   Models.swift  OrbitGuide.swift  ScanViewModel.swift
    UI/     ScanView.swift  ScanViewController.swift  ScanOverlayView.swift
    Bridge/ AprilTagDetector.swift
  Native/
    AprilTagBridge.h
    AprilTagBridge.mm
    GabaritScan-Bridging-Header.h
    apriltag/   ← (cloné depuis GitHub)
  Resources/
    Info.plist
```

**Settings Xcode requis :**
| Réglage | Valeur |
|---------|--------|
| iOS Deployment Target | 16.0 |
| Swift Language Version | 5.9 |
| Objective-C Bridging Header | `GabaritScan/Native/GabaritScan-Bridging-Header.h` |
| Frameworks | ARKit, AVFoundation, UIKit, CoreVideo |
| Other C Flags | `-DTAG36H11` |

---

## Étape 3 — Configurer Codemagic (gratuit, 500 min/mois)

1. Aller sur **[codemagic.io](https://codemagic.io)** → Sign up with GitHub
2. **Add application** → choisir ton repo `GabaritScan-iOS`
3. Codemagic détecte `codemagic.yaml` automatiquement
4. Cliquer **Start new build** → workflow `ios-debug-altserver`
5. Attendre ~15 min → télécharger le `.ipa` depuis les **Artifacts**

> 💡 **500 min gratuits** = environ 30 builds debug. Largement suffisant pour la Phase 1.

---

## Étape 4 — Installer AltServer sur Windows

### Prérequis
1. Installer **iTunes** (version Microsoft Store) : [lien](https://apps.microsoft.com/store/detail/iTunes/9PB2MZ1ZMB1S)
2. Installer **iCloud** (version Microsoft Store) : [lien](https://apps.microsoft.com/store/detail/iCloud/9PKTQ5699M62)
3. Télécharger **AltServer** depuis [altstore.io](https://altstore.io) → `AltInstaller.zip`
4. Extraire → lancer `AltInstaller.exe` → **Install AltServer**

### Installer AltStore sur l'iPhone (une seule fois)
1. Brancher l'iPhone en USB
2. Ouvrir AltServer (icône dans la barre système)
3. Cliquer l'icône → **Install AltStore** → choisir ton iPhone
4. Sur l'iPhone : Réglages → Général → VPN et gestion d'appareils → Faire confiance

### Installer le .IPA
1. Télécharger `GabaritScan.ipa` depuis Codemagic
2. Clic droit sur l'IPA dans l'explorateur
3. **AltServer → Sideload with AltServer** → choisir ton iPhone

OU dans AltStore sur l'iPhone :
- **My Apps** → `+` → choisir le `.ipa` depuis les fichiers

---

## Étape 5 — Re-signer tous les 7 jours (compte gratuit)

Avec un compte Apple gratuit, l'app expire après **7 jours**. Solutions :

**Option A — AltStore via Wi-Fi (automatique)**
- iPhone et PC sur le même Wi-Fi
- AltStore rafraîchit automatiquement quand AltServer tourne en arrière-plan

**Option B — Compte Apple Developer ($99/an)**
- L'app est valable **1 an**
- Décommenter le workflow `ios-release-testflight` dans `codemagic.yaml`
- Distribution via TestFlight (jusqu'à 100 testeurs)

---

## Différences iOS vs Android

| Aspect | Android (S24 Ultra) | iOS (iPhone 12 Pro Max) |
|--------|--------------------|-----------------------|
| Tracking AR | ARCore | ARKit 4 (**plus précis**) |
| Caméra API | CameraX (YUV_420_888) | AVFoundation (420f) |
| Intrinsèques | Approchées + calibration | `AVCameraCalibrationData` (**direct !**) |
| LiDAR | Non (ML depth) | ✅ Physique disponible (Phase 4) |
| Build | Gradle + NDK (Windows OK) | Xcode (Mac requis → Codemagic) |
| Distribution test | ADB USB direct | AltServer (7j) ou TestFlight |
| Perf AprilTag | Snapdragon 8 Gen 3 | A14 Bionic (comparable) |

---

## Avantage iPhone 12 Pro Max : intrinsèques caméra exactes

Sur iOS, `AVCameraCalibrationData` donne directement `fx, fy, cx, cy` calibrés en usine :

```swift
// Dans ScanViewController, activer AVCaptureDepthDataOutput (Phase 2) :
func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                     didOutput depthData: AVDepthData, ...) {
    let calib = depthData.cameraCalibrationData
    viewModel.intrinsics = CameraIntrinsics(
        fx: calib.intrinsicMatrix[0][0],
        fy: calib.intrinsicMatrix[1][1],
        cx: calib.intrinsicMatrix[2][0],
        cy: calib.intrinsicMatrix[2][1]
    )
}
```

> Ça évite d'avoir à faire la calibration damier !

---

## Limites Phase 1

- `solvePnP` simplifié (DLT) → erreur ~2–5° sur la pose du tag
- Phase 2 : remplacer par OpenCV iOS (`solvePnPRansac` + mode `IPPE`)
- LiDAR non utilisé (activable en Phase 4 gratuitement)
- Pas de capture JPEG réelle (Phase 2 : `AVCapturePhotoOutput`)

---

## Références

- [AltStore / AltServer](https://altstore.io)
- [Codemagic](https://codemagic.io/start/)
- [ARKit — Apple Developer](https://developer.apple.com/augmented-reality/arkit/)
- [AVFoundation](https://developer.apple.com/documentation/avfoundation)
- [AprilTag C](https://github.com/AprilRobotics/apriltag)
