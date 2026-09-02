"""Write the Info.plist that Godot reads to resolve a macOS framework's binary."""

import os
import sys

TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleExecutable</key>
\t<string>{name}</string>
\t<key>CFBundleIdentifier</key>
\t<string>me.iamtalon.godot_direct_touch</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>{name}</string>
\t<key>CFBundlePackageType</key>
\t<string>FMWK</string>
\t<key>CFBundleShortVersionString</key>
\t<string>0.1.0</string>
\t<key>CFBundleSupportedPlatforms</key>
\t<array>
\t\t<string>MacOSX</string>
\t</array>
\t<key>CFBundleVersion</key>
\t<string>0.1.0</string>
\t<key>LSMinimumSystemVersion</key>
\t<string>10.15</string>
</dict>
</plist>
"""


def write(framework_dir):
    name = os.path.basename(framework_dir)
    if name.endswith(".framework"):
        name = name[: -len(".framework")]
    resources = os.path.join(framework_dir, "Resources")
    os.makedirs(resources, exist_ok=True)
    with open(os.path.join(resources, "Info.plist"), "w") as f:
        f.write(TEMPLATE.format(name=name))
    return os.path.join(resources, "Info.plist")


if __name__ == "__main__":
    print(write(sys.argv[1]))
