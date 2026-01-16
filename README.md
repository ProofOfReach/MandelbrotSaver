# Mandelbrot Screensaver

A real-time GPU-rendered Mandelbrot and Julia set screensaver for macOS.

## Features

- **Real-time Metal GPU rendering** - Smooth 60fps fractal zooming
- **24 color palettes** - From classic Ultra to Neon, Vapor, and Candy
- **Julia set mode** - Alternates between Mandelbrot and beautiful Julia sets
- **P3 wide gamut colors** - Takes advantage of modern Mac displays
- **Blinn-Phong 3D lighting** - Optional enhanced shading with specular highlights
- **Smooth fade transitions** - Elegant fades between zoom targets
- **Configuration panel** - Adjust speed, palettes, shading, and Julia mode

## Requirements

- macOS 12.0 or later
- **No Xcode needed** to install from the release zip
- Xcode required only if building from source

## Installation

### From Release

1. Download `MandelbrotSaver.saver.zip` from Releases
2. Unzip and double-click `MandelbrotSaver.saver`
3. Choose "Install for this user only" or "Install for all users"
4. Open System Settings → Screen Saver and select "Mandelbrot"

### From Source

```bash
git clone https://github.com/yourusername/MandelbrotSaver.git
cd MandelbrotSaver
./build.sh --install
```

## Configuration

Click **Options** in System Settings → Screen Saver to configure:

- **Zoom Speed** - How fast to zoom into fractals
- **Palette** - Choose from 24 color schemes
- **Auto-cycle Palettes** - Gradually transition between palettes
- **Shading Mode** - Flat, 3D Blinn-Phong, Angle, or Stripe
- **Julia Set Mode** - Enable to see Julia sets every 4th zoom

## Building

Requires Xcode with Metal compiler:

```bash
./build.sh           # Build only
./build.sh --install # Build and install to ~/Library/Screen Savers/
```

## License

MIT License - Free to use, modify, and distribute.
