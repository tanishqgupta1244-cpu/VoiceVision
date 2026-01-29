# Troubleshooting Black Screen Issue

## Quick Checks

### 1. Check Xcode Console
- In Xcode, go to **View → Debug Area → Show Debug Area** (or press `Cmd+Shift+Y`)
- Make sure the console filter is set to "All Output" (not just errors)
- Look for messages starting with "DEBUG:" or "ERROR:"

### 2. Check Device Console (if Xcode console doesn't work)
- Connect your iPhone to your Mac
- Open **Console.app** (Applications → Utilities → Console)
- Select your iPhone from the sidebar
- Filter by your app name "blind-navigation"
- Look for crash logs or error messages

### 3. Check Camera Permissions
- On your iPhone, go to **Settings → Privacy & Security → Camera**
- Make sure "blind-navigation" has camera access enabled
- If not, enable it and restart the app

### 4. Check iOS Version
- The app requires iOS 17.0 or later
- Go to **Settings → General → About** on your iPhone
- Verify your iOS version is 17.0 or higher

### 5. Check for Crash Logs
- In Xcode, go to **Window → Devices and Simulators**
- Select your iPhone
- Click "View Device Logs"
- Look for recent crashes of "blind-navigation"

### 6. Rebuild and Clean
- In Xcode: **Product → Clean Build Folder** (Shift+Cmd+K)
- Then: **Product → Build** (Cmd+B)
- Then: **Product → Run** (Cmd+R)

### 7. Check ML Model
- Verify that `yolo11n.mlpackage` is included in the app bundle
- In Xcode, select the file in Project Navigator
- Check "Target Membership" - it should be checked for "blind-navigation"

## Common Issues

### Issue: App crashes immediately
**Solution**: Check the crash log in Xcode (Window → Devices and Simulators → View Device Logs)

### Issue: Camera permission denied
**Solution**: 
1. Delete the app from your iPhone
2. Rebuild and install from Xcode
3. Grant camera permission when prompted

### Issue: Console shows nothing
**Solution**: 
1. Make sure you're running in Debug mode (not Release)
2. Check Console.app on your Mac instead
3. Try adding `print()` statements directly in `blind_navigationApp.swift`

### Issue: ARKit not supported
**Solution**: ARKit requires an iPhone 6s or later with iOS 11+. If your device is older, the app won't work.

## Debug Steps

1. **Add a simple test view** to verify SwiftUI is working:
   - The app now shows a loading screen initially
   - If you see "Initializing AR Camera..." - SwiftUI is working
   - If you see an error message - the error is displayed

2. **Check if AR session starts**:
   - Look for "DEBUG: AR session started successfully" in console
   - If you don't see this, AR session failed to start

3. **Verify ML model loads**:
   - Look for "DEBUG: DetectionService initialized successfully"
   - If you see "ERROR: Failed to initialize DetectionService" - ML model issue

## Still Not Working?

If none of the above helps, try:
1. Create a new test project with just a simple "Hello World" view
2. If that works, the issue is specific to this app
3. If that also shows black screen, it's an Xcode/device configuration issue
