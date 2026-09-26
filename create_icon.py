import os
import subprocess
from Cocoa import (
    NSImage, NSBitmapImageRep, NSGraphicsContext, NSRect, NSPoint, NSSize,
    NSBezierPath, NSColor, NSGradient, NSFont, NSString, NSDictionary,
    NSCompositingOperationSourceOver, NSPNGFileType
)

iconset_dir = "/Users/ugurmac/DiskBar/AppIcon.iconset"
os.makedirs(iconset_dir, exist_ok=True)

sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for s, filename in sizes:
    rep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, s, s, 8, 4, True, False, "NSCalibratedRGBColorSpace", 0, 32
    )
    context = NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    NSGraphicsContext.setCurrentContext_(context)
    
    # 1. macOS Squircle Arka Plan (Zarif Koyu Mavi - Mor Gradyan)
    margin = s * 0.05
    rect = NSRect(NSPoint(margin, margin), NSSize(s - 2*margin, s - 2*margin))
    corner_radius = s * 0.22
    path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(rect, corner_radius, corner_radius)
    
    color1 = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.12, 0.14, 0.22, 1.0)
    color2 = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.06, 0.07, 0.12, 1.0)
    gradient = NSGradient.alloc().initWithStartingColor_endingColor_(color1, color2)
    gradient.drawInBezierPath_angle_(path, -45.0)
    
    # İnce çerçeve
    NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.15).setStroke()
    path.setLineWidth_(max(1.0, s * 0.015))
    path.stroke()
    
    # 2. Sürücü / Disk Çizimi (Neon Mavi & Cam efekti)
    disk_w = s * 0.60
    disk_h = s * 0.45
    disk_x = (s - disk_w) / 2
    disk_y = (s - disk_h) / 2 - (s * 0.02)
    disk_rect = NSRect(NSPoint(disk_x, disk_y), NSSize(disk_w, disk_h))
    disk_path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(disk_rect, s * 0.06, s * 0.06)
    
    d_color1 = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.18, 0.22, 0.35, 1.0)
    d_color2 = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.10, 0.12, 0.20, 1.0)
    d_gradient = NSGradient.alloc().initWithStartingColor_endingColor_(d_color1, d_color2)
    d_gradient.drawInBezierPath_angle_(disk_path, 90.0)
    
    # Disk Çerçevesi
    NSColor.colorWithCalibratedRed_green_blue_alpha_(0.3, 0.6, 1.0, 0.6).setStroke()
    disk_path.setLineWidth_(max(1.0, s * 0.018))
    disk_path.stroke()
    
    # 3. İlerleme Halkası / Led Çizimi
    led_radius = s * 0.035
    led_x = disk_x + disk_w - (s * 0.09)
    led_y = disk_y + disk_h - (s * 0.09)
    led_rect = NSRect(NSPoint(led_x - led_radius, led_y - led_radius), NSSize(led_radius * 2, led_radius * 2))
    led_path = NSBezierPath.bezierPathWithOvalInRect_(led_rect)
    NSColor.colorWithCalibratedRed_green_blue_alpha_(0.2, 0.9, 0.4, 0.9).setFill()
    led_path.fill()
    
    # 4. Hafıza / Depolama Çubukları
    bar_w = disk_w * 0.6
    bar_h = s * 0.04
    bar_x = disk_x + (s * 0.08)
    bar_y = disk_y + (disk_h * 0.35)
    bar_rect = NSRect(NSPoint(bar_x, bar_y), NSSize(bar_w, bar_h))
    bar_path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(bar_rect, bar_h/2, bar_h/2)
    NSColor.colorWithCalibratedWhite_alpha_(1.0, 0.15).setFill()
    bar_path.fill()
    
    # Doluluk barı (Mavi)
    fill_bar_w = bar_w * 0.72
    fill_bar_rect = NSRect(NSPoint(bar_x, bar_y), NSSize(fill_bar_w, bar_h))
    fill_bar_path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(fill_bar_rect, bar_h/2, bar_h/2)
    NSColor.colorWithCalibratedRed_green_blue_alpha_(0.0, 0.65, 1.0, 0.9).setFill()
    fill_bar_path.fill()
    
    png_data = rep.representationUsingType_properties_(NSPNGFileType, None)
    out_path = os.path.join(iconset_dir, filename)
    png_data.writeToFile_atomically_(out_path, True)

# iconutil ile derle
icns_path = "/Users/ugurmac/DiskBar/AppIcon.icns"
subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
print("ICNS oluşturuldu:", icns_path)
