<h1 align="center">
  <img src="/DesktopRenamer/Assets.xcassets/AppIcon.appiconset/DesktopRenamer-macOS-Default-512x512@1x.png" width="30%" alt=""/>  
  <p align="center">DesktopRenamer</p>
</h1>

<p align="center">
  <b>DesktopRenamer</b> is a macOS menubar app that shows your <b>customized</b> name of the current desktop.
</p>

<p align="center">
  <img src="/DesktopRenamer/Resources/Demo_1_Menubar.png" width="50%" ><br>
  <i>Rename the desktop label in menubar</i>
</p>

<p align="center">
  <img src="/DesktopRenamer/Resources/Demo_2_SLW.png" width="50%"><br>
  <I><b>DesktopLabelWindow</b> will be shown when entering Mission Control</i>

## Easy to Install

You do **NOT** have to disable *SIP* or things like that. Your macOS must be at least **macOS 13.0 Ventura**. All you need to do is:

1. Download the package from [Releases](https://github.com/gitmichaelqiu/DesktopRenamer/releases/)
2. Drag the app to the *Applications* folder
3. All set!

Because I do not have an Apple developer account, you may receive alerts such as "App is broken". To resolve this, you need to go to *terminal* and run the following command:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/DesktopRenamer.app
```

You may be required to enter the password. This is required by Apple. This app will **NOT** steal your password or personal information.

## Tips

Currently, you may need to start the app at the Main Desktop. Otherwise, the desktop names may be misplaced. I'm finding workarounds to resolve this issue.

## Any Issues

Create issues in [GitHub Issues](https://github.com/gitmichaelqiu/DesktopRenamer/issues).

## How to Support

You can simply click on the **Star** to support this project for free. Thank you for your support!
