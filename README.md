# Hosty

A macOS menu bar app for managing `/etc/hosts` file with profiles.

## Features

- **Multiple Profiles**: Create and manage different host configurations
- **Quick Switching**: Switch between profiles with one click from the menu bar
- **Profile Management**: Add, edit, and delete host entries
- **Backup & Restore**: Automatic backups before applying changes
- **DNS Cache Flush**: Automatically clears DNS cache when applying profiles

## Requirements

- macOS 14.0+
- Xcode 15.0+

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/Hosty.git
cd Hosty
```

2. Open `Hosty.xcodeproj` in Xcode

3. Update the following in Xcode project settings:
   - **Bundle Identifier**: Change `com.ahmetonol.Hosty` to your own
   - **Development Team**: Select your Apple Developer Team

4. Build and run the project

## Usage

1. Launch Hosty - it will appear in the menu bar
2. Click the menu bar icon to access profiles
3. Use the Editor to create and manage profiles
4. Add host entries to your profiles
5. Click "Apply" to activate a profile

## Note

Modifying the `/etc/hosts` file requires administrator privileges. Hosty will prompt for your password when applying profiles.

## License

MIT License - see [LICENSE](LICENSE) file for details.
