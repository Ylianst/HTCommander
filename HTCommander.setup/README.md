# HTCommander Installer

This folder contains the installer project for HTCommander.

## Overview

There are two installer approaches in this folder:

1. **WiX Installer (Recommended)** - Modern, command-line buildable MSI installer
2. **Visual Studio Installer Project (Legacy)** - `.vdproj` file that only works within Visual Studio IDE

## WiX Installer (Recommended)

The WiX-based installer uses WiX Toolset v5 and can be built from the command line.

### Prerequisites

- .NET SDK 8.0 or later
- WiX Toolset will be automatically downloaded via NuGet during build

### Building the Installer

#### Option 1: Using the build script

```batch
cd HTCommander.setup
build-installer.bat Release
```

#### Option 2: Using dotnet CLI directly

```batch
# First, publish the application
dotnet publish ..\src\HTCommander.csproj -c Release -r win-x64 --self-contained false

# Then build the installer
dotnet build HTCommander.Installer.wixproj -c Release
```

### Output

The MSI installer will be created at:
```
HTCommander.setup\bin\Release\HTCommander.msi
```

### Files

| File | Description |
|------|-------------|
| `HTCommander.Installer.wixproj` | WiX project file |
| `Package.wxs` | WiX source defining the installer |
| `License.rtf` | License text shown during installation |
| `build-installer.bat` | Build script for easy building |

## Visual Studio Installer Project (Legacy)

The `HTCommander.setup.vdproj` file is a legacy Visual Studio Deployment Project that:

- **Cannot be built from command line** - Only works within Visual Studio IDE
- **Requires extension** - Needs "Microsoft Visual Studio Installer Projects" extension installed
- **Not recommended** for automated builds

### Installing the Extension

If you need to use the .vdproj file:

1. Open Visual Studio
2. Go to Extensions → Manage Extensions
3. Search for "Microsoft Visual Studio Installer Projects"
4. Install and restart Visual Studio

## Installer Features

The installer includes:

- ✅ Installs HTCommander application and all dependencies
- ✅ Creates Start Menu shortcuts
- ✅ Creates Desktop shortcut
- ✅ Adds entry to Programs and Features (Add/Remove Programs)
- ✅ Supports upgrade from previous versions
- ✅ Per-user installation (no admin rights required)
- ✅ Includes web folder for embedded web server

## Customization

### Changing Version Number

Edit `HTCommander.Installer.wixproj` and update:
```xml
<ProductVersion>0.50.0</ProductVersion>
```

### Changing Install Location

The default install location is:
```
C:\Program Files\Open Source\HTCommander
```

Edit `Package.wxs` to modify the directory structure.

## Troubleshooting

### "WiX Toolset not found"

The WiX Toolset SDK should be automatically downloaded. If issues occur:

```batch
dotnet restore HTCommander.Installer.wixproj
```

### Build errors about missing files

Ensure the main project builds successfully first:

```batch
dotnet build ..\src\HTCommander.csproj -c Release
```

### ICE validation errors

ICE validation warnings during build are usually informational. To suppress:

Add to `HTCommander.Installer.wixproj`:
```xml
<PropertyGroup>
  <SuppressIces>ICE61;ICE91</SuppressIces>
</PropertyGroup>