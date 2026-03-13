GlassOPT — Installation Guide
Installation
```
\\\
When launching the GlassOTP app for the first time, it will ask several times for permission to create
and modify its folder in the Keychain. Unfortunately, it may also request these permissions again after
updates. However, once the permissions are granted (sometimes multiple times), everything works correctly 
and the keys are not reset.
\\\
```
Extract the downloaded ZIP archive.

Move GlassOPT.app to your Applications folder.

Launch the application by holding the Control key and clicking the app, then select Open.

macOS Security Warning (AutoFix)

On newer versions of macOS, you may see a security warning saying that the application is damaged and cannot be opened. This happens because macOS Gatekeeper blocks apps that are not signed by an identified developer.

Example warning:

“The application ‘Example’ is damaged and can’t be opened. You should move it to the Trash.”

If you encounter this issue, you can fix it using the included AutoFix tool.

Using AutoFix

Launch AutoFix.app.

If this is the first launch, you may see the message:

“The application ‘Auto Fix’ can’t be opened because the developer cannot be verified.”

How to open it:

Right-click (or hold Control and click) on AutoFix.app

Select Open from the context menu

In the dialog window, click Open again to confirm

After opening AutoFix, select GlassOPT.app and run the fix.

What AutoFix Does

AutoFix runs several system commands with sudo privileges to remove macOS security flags and fix permissions:
```
xattr -c -r
xattr -r -d
chmod +x
chown -R $USER
chmod -R 777
```

These commands:

Remove extended attributes added by macOS

Fix application permissions

Ensure the application can run properly

After Fixing

Once the process is complete, GlassOPT should launch normally without macOS blocking it.


If you do not want to use AutoFix, you can simply run the following command:
```
sudo xattr -r -c /Applications/LockedApp.app
```
Replace LockedApp.app with the name of the damaged application.
