Just Move GlassOPT ( in zip folder ) to your AppFolder and start it up with control key =) 
+ AutoFix app for new MacOS
On the first launch, you may see the message:
“The application ‘Auto Fix’ can’t be opened because the developer cannot be verified.”
Solution:

Right-click Auto Fix (or hold the Control key and click the application).
In the context menu, select Open.
In the dialog window that appears, click Open again to confirm.

What the script does:
The script executes the following commands with sudo privileges:
xattr -c -r
xattr -r -d
chmod +x
chown -R $USER
chmod -R 777

These commands remove extended attributes, adjust permissions, and ensure the application can be executed properly.
